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

inline float Cos2Theta(float3 w) {
    return w.z * w.z;
}

inline float Sin2Theta(float3 w) {
    return fmax(0.0f, 1.0f - Cos2Theta(w));
}
inline float SinTheta(float3 w) {
    return sqrt(Sin2Theta(w));
}

inline float CosPhi(float3 w) {
    float sinTheta = SinTheta(w);
    return (sinTheta == 0.0f) ? 1.0f : clamp(w.x / sinTheta, -1.0f, 1.0f);
}

inline float SinPhi(float3 w) {
    float sinTheta = SinTheta(w);
    return (sinTheta == 0.0f) ? 0.0f : clamp(w.y / sinTheta, -1.0f, 1.0f);
}

inline float Tan2Theta(float3 w) {
    return Sin2Theta(w) / Cos2Theta(w);
}

float Lambda(float3 w, float a)
{
    float tan2Theta = Tan2Theta(w);
    if (isinf(tan2Theta))
        return 0.0f;
    float alpha2 = (CosPhi(w) * a) * (CosPhi(w) * a) + (SinPhi(w) * a) * (SinPhi(w) * a);
    return (sqrt(1.0f + alpha2 * tan2Theta) - 1.0f) / 2.0f;
}

// https://www.pbr-book.org/4ed/Reflection_Models/Roughness_Using_Microfacet_Theory#
float G_pbrt(float3 wo, float3 wi, float3 N, float roughness)
{
    mat4x4 mat, matInv;
    float4 localIn, localOut;
    float4 globalIn, globalOut;

    globalIn.xyz = wi;
    globalIn.w = 0.0f;
    globalOut.xyz = wo;
    globalOut.w = 0.0f;

    GetNormalSpace(N, &mat);
    InverseMat4x4(&mat, &matInv);
    MultiplyMat4Vec4(&matInv, &globalOut, &localOut);
    MultiplyMat4Vec4(&matInv, &globalIn, &localIn);

    if (localIn.z < 0 || localOut.z < 0)
        return 0.0f;

    return 1 / (1 + Lambda(localIn.xyz, roughness) + Lambda(localOut.xyz, roughness));
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
    // float  G = G_Smith_Disney(dotNL, dotNV, roughness);
    float G = G_pbrt(V, L, N, roughness);
    float3 F = F_Schlick(dotVH, metallic, albedo);

    float3 c_diff = albedo * (1.0f - metallic);
    float3 f_diffuse  = (1 - F) * (1 / PI) * c_diff;
    float3 f_specular = F * D * G / max(4.0f * dotNL * dotNV, 0.001f);

    color += (f_diffuse + f_specular) * (dotNL);
	return color;
}

float3 reflect(float3 in, float3 N)
{
    return -in + 2 * dot(in, N) * N;
}

float3 refract(float3 V, float3 H, float eta)
{
    float cosTheta_i = dot(H, V);
    float sin2Theta_i = max(0.0f, 1.0f - (cosTheta_i * cosTheta_i));
    float sin2Theta_t = sin2Theta_i / (eta * eta);

    if ((1.0f - sin2Theta_t) < 0.0f)
        return 0.0f;
    float cosTheta_t = sqrt(1.0f - sin2Theta_t);
    return -V / eta + (cosTheta_i / eta - cosTheta_t) * H;
}

float3 refract_glsl(float3 I, float3 N, float eta)
{
    float3 R;
    float k = 1.0f - eta * eta * (1.0f - dot(N, I) * dot(N, I));
    if (k < 0.0f)
        R = 0.0f;
    else
        R = eta * I - (eta * dot(N, I) + sqrt(k)) * N;
    return R;
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
        float3 reflectance = (baseColor) * (1.0f - metallicness);
        float3 f_diffuse  = reflectance * (1 - F); // brdf of diffuse
        *nextFactor = f_diffuse;
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

		float3 L = reflect(V, H.xyz);

		// all required dot products
		float NoV = clamp(dot(N, V), 0.0f, 1.0f);
		float NoL = clamp(dot(N, L), 0.0f, 1.0f);
		float NoH = clamp(dot(N, H.xyz), 0.0f, 1.0f);
		float VoH = clamp(dot(V, H.xyz), 0.0f, 1.0f);

		// specular microfacet (cook-torrance) BRDF
        roughness = max(0.05f, roughness);

		float  D = D_GGX(NoH, roughness);
        // float  G = G_Smith_Disney(NoL, NoV, roughness);
        float G = G_pbrt(V, L, N, roughness);
        float3 F = F_Schlick(VoH, metallicness, baseColor);

		*nextFactor = F * G * VoH / max((NoH * NoV), 0.001f);
		*nextFactor *= 2.0f; // compensate for splitting diffuse and specular
		return L;
	}
}

float3 microfacetBRDF(float3 L, float3 V, float3 N, float3 albedo,
    float metallicness, float roughness, float transmission, float ior)
{
    float3 H = normalize(V + L); // half vector

    // all required dot products
    float NoV = clamp(dot(N, V), 0.0f, 1.0f);
    float NoL = clamp(dot(N, L), 0.0f, 1.0f);
    float NoH = clamp(dot(N, H), 0.0f, 1.0f);
    float VoH = clamp(dot(V, H), 0.0f, 1.0f);     

    float3 F = F_Schlick(VoH, metallicness, albedo);
    float  D = D_GGX(NoH, roughness); 
    float  G = G_pbrt(V, L, N, roughness);

    float3 f_specular = (D * G * F) / max(4.0f * NoV * NoL, 0.001f);
    float3 notSpec = (1.0f - F) * (1.0f - metallicness) * (1.0f - transmission);
    float3 f_diffuse = notSpec * (albedo / PI);
    return (f_diffuse + f_specular) * NoL;
}

float3 sampleMicrofacetBRDF_transm(float3 V, float3 N, float3 baseColor,
    float metallicness, float roughness, float transmission, float ior,
    float3 random, float3* nextFactor)
{
    if(random.z < 0.5f)
    {   // non-specular light
        if((2.0f * random.z) < transmission)
        {
            // transmitted light
            float3 forwardNormal = N;
            float frontFacing = dot(V, N);
            float eta = ior;
            if(frontFacing < 0.0f) {
                forwardNormal = -N;
                eta = 1.0f / ior;
            }
            
            float a = roughness * roughness;
            float theta = acos(sqrt((1.0f - random.y) / (1.0f + (a * a - 1.0f) * random.y)));
            float phi = 2.0 * PI * random.x;

            float4 localH = {sin(theta) * cos(phi), sin(theta) * sin(phi), cos(theta), 0.0f};
            mat4x4 mat; float4 tmp;
            GetNormalSpace(forwardNormal, &mat);
            MultiplyMat4Vec4(&mat, &localH, &tmp);
                
            // compute L from sampled H
            float3 H = tmp.xyz;
            float3 L = refract(V, H, eta);
            
            // all required dot products
            float NoV = clamp(dot(forwardNormal, V), 0.0f, 1.0f);
            float NoL = clamp(dot(forwardNormal, -L), 0.0f, 1.0f); // reverse normal
            float NoH = clamp(dot(forwardNormal, H), 0.0f, 1.0f);
            float VoH = clamp(dot(V, H), 0.0f, 1.0f);     
            
            float3 F = F_Schlick(VoH, metallicness, baseColor);
            float  D = D_GGX(NoH, roughness);
            float  G = G_pbrt(V, -L, forwardNormal, roughness);
            *nextFactor = baseColor * (1.0f - F) * G * VoH / max((NoH * NoV), 0.001f);
            
            *nextFactor *= 2.0f; // compensate for splitting diffuse and specular
            return L;
        }
        else
        { // diffuse light
        
            // important sampling diffuse
            float theta = acos(sqrt(random.y));
            float phi = 2.0f * PI * random.x;
            // sampled indirect diffuse direction in normal space
            float4 localDiffuseDir = {sin(theta) * cos(phi), sin(theta) * sin(phi), cos(theta), 0.0f};
            mat4x4 mat; float4 tmp;
            GetNormalSpace(N, &mat);
            MultiplyMat4Vec4(&mat, &localDiffuseDir, &tmp);

            float3 L = tmp.xyz;
            float3 H = normalize(V + L);
            float VoH = clamp(dot(V, H), 0.0f, 1.0f);     
            float3 F = F_Schlick(VoH, metallicness, baseColor);
            
            *nextFactor = (1.0f - F) * (1.0f - metallicness) * baseColor;
            *nextFactor *= 2.0f; // compensate for splitting diffuse and specular
            return L;
        }
    }
    else
    {// specular light
        
        // important sample GGX
        float a = roughness * roughness;
		float theta = acos(sqrt((1.0f - random.y) / (1.0f + (a * a - 1.0f) * random.y)));
		float phi = 2.0f * PI * random.x;

		float4 localH = {sin(theta) * cos(phi), sin(theta) * sin(phi), cos(theta), 0.0f};
        mat4x4 mat; float4 tmp;
        GetNormalSpace(N, &mat);
        MultiplyMat4Vec4(&mat, &localH, &tmp);

        float3 H = tmp.xyz;
        float3 L = reflect(V, H);

        // all required dot products
        float NoV = clamp(dot(N, V), 0.0f, 1.0f);
        float NoL = clamp(dot(N, L), 0.0f, 1.0f);
        float NoH = clamp(dot(N, H), 0.0f, 1.0f);
        float VoH = clamp(dot(V, H), 0.0f, 1.0f);     
        
        float  D = D_GGX(NoH, roughness);
        float  G = G_pbrt(V, L, N, roughness);
        float3 F = F_Schlick(VoH, metallicness, baseColor);

        *nextFactor =  F * G * VoH / max((NoH * NoV), 0.001f);
        *nextFactor *= 2.0f; // compensate for splitting diffuse and specular
        return L;
    }
}

struct Material
{
    float4 albedo;

    float metallic;
    float roughness;
    float transmission;
    float ior;

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
