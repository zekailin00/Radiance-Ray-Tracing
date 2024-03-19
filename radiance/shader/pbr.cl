const float PI = 3.14159265359;

// Normal Distribution function --------------------------------------
float D_GGX(float dotNH, float roughness)
{
	float alpha = roughness * roughness;
	float alpha2 = alpha * alpha;
	float denom = dotNH * dotNH * (alpha2 - 1.0) + 1.0;
	return (alpha2)/(PI * denom*denom); 
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

float3 BRDF(float3 L, float3 V, float3 N, float metallic, float roughness, float3 albedo, float3 lightColor)
{
	// Precalculate vectors and dot products	
	float3 H = normalize (V + L);
	float dotNV = fabs(dot(N, V));
	float dotNL = fabs(dot(N, L));
	float dotNH = fabs(dot(N, H));

	float3 color = {0.0f, 0.0f, 0.0f};
	if (dot(N, L) > 0.0)
	{
		float rroughness = max(0.05f, roughness);

		float D = D_GGX(dotNH, roughness); 
		float G = G_SchlicksmithGGX(dotNL, dotNV, rroughness);
		float3 F = F_Schlick(dotNV, metallic, albedo);

		float3 c_diff = albedo * (1.0f - metallic);
		float3 f_diffuse = (1 - F) * (1 / PI) * c_diff;
		float3 f_specular = F * D * G / (4.0f * dotNL * dotNV);

		color += (f_diffuse + f_specular) * (dotNL * lightColor);
	}

	return color;
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


float4 CalculatePixelColor(
    struct Material* material, struct SceneProperties* scene,
    float3* hitPos, float3* viewPos, float3* normal/*, float2* texCoords*/)
{
	float3 N = normalize(*normal);
	float3 V = normalize(*viewPos - *hitPos);

    float metallicFrag;
    float roughnessFrag;
    float3 albedoFrag;

    if (material->useMetallicTex == 0)
        metallicFrag = material->metallic;
    // else
    //     metallicFrag = texture(MetallicTexture, texCoords).x;

    if (material->useRoughnessTex == 0)
        roughnessFrag = clamp(material->roughness, 0.0f, 1.0f);
    // else
    //     roughnessFrag = clamp(texture(RoughnessTexture, texCoords).x, 0.0, 1.0);

    if (material->useAlbedoTex == 0)
        albedoFrag = material->albedo.rgb;
    // else
    //     albedoFrag = texture(AlbedoTexture, texCoords).rgb;

	// Specular contribution
	float3 Lo = {0.0f, 0.0f, 0.0f};
	for (int i = 0; i < scene->lightCount.x; i++)
    {
		float3 L = normalize(scene->lights[i].direction.xyz);
        float3 lightColor = scene->lights[i].color.rgb;
		Lo += BRDF(L, V, N, metallicFrag, roughnessFrag, albedoFrag, lightColor);
	}

	// Combine with ambient
	float3 color = albedoFrag * 0.02f;
	color += Lo;

    // HDR mapping
    color = color / (color + 1.0f);

	// Gamma correct
	color = pow(color, 0.4545f);

    float4 fragColor = {color.xyz, 1.0f};
    return fragColor;
}