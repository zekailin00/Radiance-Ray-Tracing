const float PI = 3.14159265359;

// Normal Distribution function --------------------------------------
float D_GGX(float dotNH, float roughness)
{
    // to do, not abs, needs direction
	float alpha = roughness * roughness;
	float alpha2 = alpha * alpha;
	float denom = dotNH * dotNH * (alpha2 - 1.0) + 1.0;
	return  (alpha2 * dotNH)/(PI * denom*denom); 
}

// Geometric Shadowing function --------------------------------------
float G_SchlicksmithGGX(float dotNL, float dotNV, float roughness)
{
	float r = (roughness + 1.0);
	float k = (r*r) / 8.0;
	float GL = dotNL / (dotNL * (1.0 - k) + k);
	float GV = dotNV / (dotNV * (1.0 - k) + k);
	return GL * GV;
}

// Fresnel function ----------------------------------------------------
float3 F_Schlick(float cosTheta, float metallic, float3 albedo)
{
    float3 minValue = {0.04f, 0.04f, 0.04f};
	float3 F0 = mix(minValue, albedo, metallic);
	float3 F = F0 + (1.0f - F0) * (float)pow(1.0 - cosTheta, 5.0);
	return F;
}

float3 BRDF(float3 L, float3 V, float3 N, float metallic, float roughness, float3 albedo)
{
	// Precalculate vectors and dot products	
	float3 H = normalize(V + L);
	float dotNV = clamp(dot(N, V), 0.0f, 1.0f);
	float dotNL = clamp(dot(N, L), 0.0f, 1.0f);
	float dotNH = clamp(dot(N, H), 0.0f, 1.0f);
	float dotVH = clamp(dot(V, H), 0.0f, 1.0f);

	float3 color = {0.0f, 0.0f, 0.0f};
	if (dot(N, L) > 0.0)
	{
		float rroughness = max(0.05f, roughness);

		float  D = D_GGX(dotNH, roughness); 
		float  G = G_SchlicksmithGGX(dotNL, dotNV, rroughness);
		float3 F = F_Schlick(dotVH, metallic, albedo);

		float3 c_diff = albedo * (1.0f - metallic);
		float3 f_diffuse  = (1 - F) * (1 / PI) * c_diff;
		float3 f_specular = F * D * G / max(4.0f * dotNL * dotNV, 0.0001f);

		color += (f_diffuse + f_specular) * (dotNL);
	}

	return color;
}

void GetNormalSpace(float3 normal, mat4x4* out)
{
    float3 someVec = {1.0, 0.0, 0.0};
    float dd = dot(someVec, normal);
    float3 tangent = {0.0, 1.0, 0.0};
    if(1.0 - fabs(dd) > 1e-6) {
        tangent = normalize(cross(someVec, normal));
    }
    float3 bitangent = cross(normal, tangent);
    
    out->s0 = tangent.x;
    out->s4 = tangent.y;
    out->s8 = tangent.z;
    out->sc = 0;

    out->s1 = bitangent.x;
    out->s5 = bitangent.y;
    out->s9 = bitangent.z;
    out->sd = 0;

    out->s2 = normal.x;
    out->s6 = normal.y;
    out->sa = normal.z;
    out->se = 0;

    out->s3 = 0;
    out->s7 = 0;
    out->sb = 0;
    out->sf = 1;
}

float3 Reflect(float3 in, float3 N)
{
    return -in + 2 * dot(in, N) * N;
}

float3 sampleMicrofacetBRDF(
    float3 V, float3 N,
    float3 baseColor, float metallicness, float roughness,
    float3 random, float3* nextFactor) 
{
	if(random.z > 0.5)
	{
		// diffuse case

		// important sampling diffuse
		// pdf = cos(theta) * sin(theta) / PI
		float theta = asin(sqrt(random.y));
		float phi = 2.0 * PI * random.x;
		// sampled indirect diffuse direction in normal space
		float4 localDiffuseDir = {sin(theta) * cos(phi), sin(theta) * sin(phi), cos(theta), 0.0f};
        mat4x4 mat; float4 L;
        GetNormalSpace(N, &mat);
        MultiplyMat4Vec4(&mat, &localDiffuseDir, &L);

		// half vector
		float3 H = normalize(V + L.xyz);
		float dotVH = clamp(dot(V, H), 0.0f, 1.0f);     
		float3 F = F_Schlick(dotVH, metallicness, baseColor);

        // dielectric diffuse(no transmission) reflectance;
        float3 reflectance = (baseColor /*TODO:/ PI?*/) * (1.0f - metallicness);
        float3 f_diffuse  = reflectance * (1 - F); // brdf of diffuse
        *nextFactor = f_diffuse;
        // *nextFactor *= (2.0f * PI); // TODO: check brdf sampling probability
		*nextFactor *= 2.0f; // compensate for splitting diffuse and specular
		return L.xyz;
	}
	else
	{
		// specular case
		
		// important sample GGX
		// pdf = D * cos(theta) * sin(theta)
		float a = roughness * roughness;
		float theta = acos(sqrt((1.0 - random.y) / (1.0 + (a * a - 1.0) * random.y)));
		float phi = 2.0 * PI * random.x;

		float4 localH = {sin(theta) * cos(phi), sin(theta) * sin(phi), cos(theta), 0.0f};
        mat4x4 mat; float4 H;
        GetNormalSpace(N, &mat);
        MultiplyMat4Vec4(&mat, &localH, &H);

		float3 L = Reflect(V, H.xyz); //FIXME: negative??

		// all required dot products
		float NoV = clamp(dot(N, V), 0.0f, 1.0f);
		float NoL = clamp(dot(N, L), 0.0f, 1.0f);
		float NoH = clamp(dot(N, H.xyz), 0.0f, 1.0f);
		float VoH = clamp(dot(V, H.xyz), 0.0f, 1.0f);     

		// specular microfacet (cook-torrance) BRDF
        float rroughness = max(0.05f, roughness);

		float  D = D_GGX(NoH, roughness);
		float  G = G_SchlicksmithGGX(NoL, NoV, rroughness);
        float3 F = F_Schlick(VoH, metallicness, baseColor);

		*nextFactor = F * G * VoH / max((NoH * NoV), 0.001f);
		*nextFactor *= 2.0f; // compensate for splitting diffuse and specular
		return L;
	}
}

struct Material
{
    float4 albedo;

    float metallic;
    float roughness;
    float _1;
    float _2;

    float useAlbedoTex;
    float useMetallicTex;
    float useRoughnessTex;
    float useNormalTex;
};

struct DirLight
{
    float4 direction;
    float4 color;
};

struct SceneProperties
{
    uint4 lightCount; // only 1st is used
    struct DirLight lights[5];
};

// layout (set = 0, binding = 1) uniform sampler2D AlbedoTexture;
// layout (set = 0, binding = 2) uniform sampler2D MetallicTexture;
// layout (set = 0, binding = 3) uniform sampler2D RoughnessTexture;
// layout (set = 0, binding = 4) uniform sampler2D NormalTexture;