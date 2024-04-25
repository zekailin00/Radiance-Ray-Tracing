#include "math.cl"

const float PI = 3.14159265359;

// Normal Distribution function --------------------------------------
float D_GGX(float dotNH, float roughness)
{
    // to do, not abs, needs direction
	float alpha = roughness * roughness;
	float alpha2 = alpha * alpha;
	float denom = dotNH * dotNH * (alpha2 - 1.0) + 1.0;
	return  (alpha2)/(PI * denom*denom); 
}

// Disney Geometric Shadowing function ----------------------------------
float G1_GGX_Schlick(float NdotV, float roughness) {
  //float r = roughness; // original
  float r = 0.5 + 0.5 * roughness; // Disney remapping
  float k = (r * r) / 2.0;
  float denom = NdotV * (1.0 - k) + k;
  return NdotV / denom;
}

float G_Smith_Disney(float NoL, float NoV, float roughness) {
  float g1_l = G1_GGX_Schlick(NoL, roughness);
  float g1_v = G1_GGX_Schlick(NoV, roughness);
  return g1_l * g1_v;
}

// Fresnel function ----------------------------------------------------
float3 F_Schlick(float cosTheta, float metallic, float3 albedo)
{
    float3 minValue = {0.04f, 0.04f, 0.04f};
	float3 F0 = mix(minValue, albedo, metallic);
	float3 F = F0 + (1.0f - F0) * (float)pow(1.0 - cosTheta, 5.0);
	return F;
}

////////////////// Not Used ////////////////////


// Geometric Shadowing function --------------------------------------
float G_SchlicksmithGGX(float dotNL, float dotNV, float roughness)
{
	float r = (roughness + 1.0);
	float k = (r*r) / 8.0;
	float GL = dotNL / (dotNL * (1.0 - k) + k);
	float GV = dotNV / (dotNV * (1.0 - k) + k);
	return GL * GV;
}

float D_GGX_not_remapped(float NoH, float roughness)
{
    //FIXME: remapping inside or outside?
    // no remapping
    float a = NoH * roughness;
    float k = roughness / (1.0 - NoH * NoH + a * a);
    return k * k * (1.0 / PI);
}

// Roughness Remapping -------------------------------------------------
float Roughness_Remap(float roughness)
{
    roughness = max(0.05f, roughness);
    roughness = roughness * roughness;
    return roughness;
}

// Geometric Shadowing function Filament -----------------------------------
float G_SmithGGXCorrelated(float NoL, float NoV, float roughness)
{
    float a2 = roughness * roughness;
    float GGXL = NoV * sqrt((-NoL * a2 + NoL) * NoL + a2);
    float GGXV = NoL * sqrt((-NoV * a2 + NoV) * NoV + a2);
    return 0.5 / (GGXV + GGXL);
}

// Disney diffuse function ----------------------------------------------
float3 Diffuse_Disney(float3 c_diff, float roughness, float dotNL, float dotNV, float dotVH)
{
    float3 reflectance =  (1 / PI) * c_diff;
    float FD90 = 0.5 + 2 * roughness * dotVH * dotVH;
    float factorNL = (1 + (FD90 - 1) * pow(1 - dotNL, 5.0f));
    float factorNV = (1 + (FD90 - 1) * pow(1 - dotNV, 5.0f));
    float3 disneyDiffuse = reflectance * factorNL * factorNV;
    return reflectance;
}

//////////////////////////////////////////////////

float3 BRDF(float3 L, float3 V, float3 N, float metallic, float roughness, float3 albedo)
{
    roughness = max(0.05f, roughness);

	float3 H = normalize(V + L);
	float dotNV = clamp(dot(N, V), 0.0f, 1.0f);
	float dotNL = clamp(dot(N, L), 0.0f, 1.0f);
	float dotNH = clamp(dot(N, H), 0.0f, 1.0f);
	float dotVH = clamp(dot(V, H), 0.0f, 1.0f);

	float3 color = {0.0f, 0.0f, 0.0f};
    float  D = D_GGX(dotNH, roughness); 
    float  G = G_Smith_Disney(dotNL, dotNV, roughness);
    float3 F = F_Schlick(dotVH, metallic, albedo);

    float3 c_diff = albedo * (1.0f - metallic);
    float3 f_diffuse  = (1 - F) * (1 / PI) * c_diff;
    float3 f_specular = F * D * G / max(4.0f * dotNL * dotNV, 0.001f);

    color += (f_diffuse + f_specular) * (dotNL);
	return color;
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
    // https://ameye.dev/notes/sampling-the-hemisphere/
	if(random.z > 0.5)
	{
		// diffuse case

		// important sampling diffuse
		// pdf = cos(theta) * sin(theta) / PI
		float theta = acos(sqrt(random.y));
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
	else // https://schuttejoe.github.io/post/ggximportancesamplingpart1/
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
        roughness = max(0.05f, roughness);

		float  D = D_GGX(NoH, roughness);
		// float  G = G_SmithGGXCorrelated(NoL, NoV, roughness*roughness);
        float  G = G_Smith_Disney(NoL, NoV, roughness);
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

    // -1 := not used
    int albedoTexIdx;
    int metallicTexIdx;
    int roughnessTexIdx;
    int normalTexIdx;
};

struct MeshInfo
{
    // -1 := not used
    int vertexOffset;
    int indexOffset;
    int uvOffset;   
    int normalOffset;

    int materialIndex;
    int _0, _1, _2;
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
