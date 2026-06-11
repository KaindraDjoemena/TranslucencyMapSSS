// light_pass.glsl

/*
 * PBR Implementation credit: https://learnopengl.com/code_viewer_gh.php?code=src/6.pbr/1.2.lighting_textured/1.2.pbr.fs
 * found in chapter: https://learnopengl.com/PBR/Lighting
*/

#TYPE VERTEX
#version 460 core
layout (location = 0) in vec3 a_Pos;
layout (location = 1) in vec3 a_Normal;
layout (location = 2) in vec2 a_TexCoords;

// ===== Light Structs =====
struct DirLightData			// Directional Lights
{
    vec4 directionAndPower; // xyz = direction, w = power
    vec4 colorAndShadow;    // xyz = color,     w = shadow (-1 = no shadows)
};
struct PointLightData		// Point Lights
{
    vec4 positionAndRange; 	// xyz = position,               w = range
    vec4 colorAndPower;    	// xyz = color,                  w = power
    vec4 shadow;           	// x = shadow (-1 = no shadows), yzw = padding (0.0f)
};
struct SpotLightData		// Spot Lights
{
    vec4 positionAndLength; // xyz = position,  w = length
    vec4 directionAndInner; // xyz = direction, w = innerCos
    vec4 colorAndOuter;     // xyz = color,     w = outerCos
    vec4 powerAndShadow;    // x = power,       y = shadow (-1.0f = no shadows), zw = padding (0.0f)
};

// ===== Instance Mats =====
struct InstanceData
{
    mat4 model;
    mat4 normal;
};


layout(std140, binding = 0) uniform CameraBuffer
{
    mat4 u_View;
    mat4 u_Projection;
    vec4 u_CameraPosAndTime;
};
layout(std430, binding = 1) readonly buffer InstanceBuffer
{
    InstanceData u_Instances[];
};
layout(std430, binding = 2) readonly buffer LightBuffer
{
    uint u_DirCount;
    uint u_PointCount;
    uint u_SpotCount;
    uint u_Padding;
    
    DirLightData   u_DirLights[4];
    PointLightData u_PointLights[4];
    SpotLightData  u_SpotLights[4];
};

uniform uint u_TransformIndex;

uniform mat4 u_DirLightSpaceMat[4];
uniform mat4 u_SpotLightSpaceMat[4];

// ===== VERTEX SHADER OUT =====
out VS_OUT {
    vec3 v_FragPos;
    vec3 v_Normal;
    vec2 v_TexCoords;

    vec4 v_FragPosDirLightSpace[4];
    vec4 v_FragPosSpotLightSpace[4];
} vs_out;


void main() 
{
    mat4 modelMat  = u_Instances[u_TransformIndex].model;
    mat3 normalMat = mat3(u_Instances[u_TransformIndex].normal);

	vs_out.v_FragPos   	 	   = vec3(modelMat * vec4(a_Pos, 1));
    vs_out.v_Normal    		   = normalMat * a_Normal;
	vs_out.v_TexCoords 		   = a_TexCoords;

	// fragment position in light space
    for(int i = 0; i < 4; i++)
	{
        vs_out.v_FragPosDirLightSpace[i]  = u_DirLightSpaceMat[i] * vec4(vs_out.v_FragPos, 1);
        vs_out.v_FragPosSpotLightSpace[i] = u_SpotLightSpaceMat[i] * vec4(vs_out.v_FragPos, 1);
    }
    
	gl_Position = u_Projection * u_View * modelMat * vec4(a_Pos, 1.0);		// world space transformation
}


#TYPE FRAGMENT
#version 460 core

const float PI = 3.141592653589793;

// ===== Light Structs =====
struct DirLightData			// Directional Lights
{
    vec4 directionAndPower; // xyz = direction, w = power
    vec4 colorAndShadow;    // xyz = color,     w = shadow (-1 = no shadows)
};
struct PointLightData		// Point Lights
{
    vec4 positionAndRange; 	// xyz = position,               w = range
    vec4 colorAndPower;    	// xyz = color,                  w = power
    vec4 shadow;           	// x = shadow (-1 = no shadows), yzw = padding (0.0f)
};
struct SpotLightData		// Spot Lights
{
    vec4 positionAndLength; // xyz = position,  w = length
    vec4 directionAndInner; // xyz = direction, w = innerCos
    vec4 colorAndOuter;     // xyz = color,     w = outerCos
    vec4 powerAndShadow;    // x = power,       y = shadow (-1.0f = no shadows), zw = padding (0.0f)
};

layout(std140, binding = 0) uniform CameraBuffer
{
    mat4 u_View;
    mat4 u_Projection;
    vec4 u_CameraPosAndTime;
};
layout(std430, binding = 2) readonly buffer LightBuffer
{
    uint u_DirCount;
    uint u_PointCount;
    uint u_SpotCount;
    uint u_Padding;
    
    DirLightData   u_DirLights[4];
    PointLightData u_PointLights[4];
    SpotLightData  u_SpotLights[4];
};


in VS_OUT {
    vec3 v_FragPos;
    vec3 v_Normal;
    vec2 v_TexCoords;

    vec4 v_FragPosDirLightSpace[4];
    vec4 v_FragPosSpotLightSpace[4];
} fs_in;

out vec4 FragColor;

layout(binding = 0) uniform sampler2D u_albedoMap;     uniform bool u_hasAlbedoMap;     uniform vec3  u_albedoFactor;
layout(binding = 1) uniform sampler2D u_normalMap;	   uniform bool u_hasNormalMap;
layout(binding = 2) uniform sampler2D u_metallicMap;   uniform bool u_hasMetallicMap;   uniform float u_metallicFactor;
layout(binding = 3) uniform sampler2D u_roughnessMap;  uniform bool u_hasRoughnessMap;  uniform float u_roughnessFactor;
layout(binding = 4) uniform sampler2D u_aoMap;		   uniform bool u_hasAOMap;		    uniform float u_AOFactor;

// IBL MAPS
layout(binding = 5) uniform samplerCube u_IrradianceMap;
layout(binding = 6) uniform samplerCube u_PrefilterMap;
layout(binding = 7) uniform sampler2D   u_BrdfLut;

layout(binding = 8) uniform sampler2D u_ThicknessMap;
layout(binding = 9) uniform sampler2D u_TransLut;
uniform bool u_hasThicknessMap;

// SHADOW MAP ARRAYS
layout(binding = 10) uniform sampler2D   u_DirShadowMaps[4];
layout(binding = 14) uniform sampler2D   u_SpotShadowMaps[4];
layout(binding = 18) uniform samplerCube u_PointShadowMaps[4];


// Shadow Calculation Helpers
float calcShadow(sampler2D shadowMap, vec4 fragPosLightSpace, float bias = 0.05);
float calcPointShadow(samplerCube shadowMap, vec3 fragPos, vec3 lightPos, float farPlane, float bias);

// Cook-Torrance BRDF Helpers
float NDF_GGXTR(vec3 N, vec3 H, float roughness);
float G_SchlickGGX(float NdotV, float roughness);
float G_Smith(vec3 N, vec3 V, vec3 L, float roughness);
vec3 F_Schlick(float cosTheta, vec3 F0);
vec3 F_SchlickR(float cosTheta, vec3 F0, float roughness);

// Material Reflections
vec3 calcDirLight(DirLightData light, vec3 N, vec3 V, float shadow, vec3 ALBEDO, float ROUGHNESS, float METALLIC, vec3 F0, float tm);
vec3 calcSpotLight(SpotLightData light, vec3 N, vec3 V, vec3 fragPos, float shadow, vec3 ALBEDO, float ROUGHNESS, float METALLIC, vec3 F0, float tm);
vec3 calcPointLight(PointLightData light, vec3 N, vec3 V, vec3 fragPos, float shadow, vec3 ALBEDO, float ROUGHNESS, float METALLIC, vec3 F0, float tm);


void main() 
{
	vec3  ALBEDO    = u_hasAlbedoMap ? pow(texture(u_albedoMap, fs_in.v_TexCoords).rgb, vec3(2.2)) : u_albedoFactor;
    vec3  NORMAL    = normalize(fs_in.v_Normal);
    float METALLIC  = u_hasMetallicMap ? texture(u_metallicMap, fs_in.v_TexCoords).b : u_metallicFactor;		// Blue channel
    float ROUGHNESS = u_hasRoughnessMap ? texture(u_roughnessMap, fs_in.v_TexCoords).g : u_roughnessFactor;		// Green channel
    float AO        = u_hasAOMap ? texture(u_aoMap, fs_in.v_TexCoords).r : u_AOFactor;							// Red channel

    float THICKNESS = u_hasThicknessMap ? texture(u_ThicknessMap, fs_in.v_TexCoords).r : 1.0;   // Red channel
    float tm = clamp(1.0 - THICKNESS, 0.0, 1.0);

	ROUGHNESS = clamp(ROUGHNESS, 0.03, 1.0);  // prevent infinitely small specular points

	vec3 N = normalize(fs_in.v_Normal);
	vec3 V = normalize(u_CameraPosAndTime.xyz - fs_in.v_FragPos);

	vec3 F0 = vec3(0.04);
	F0 = mix(F0, ALBEDO, METALLIC);
	
	vec3 Lo = vec3(0.0);

	const float shadowBias = 0.005;

	// ----- PBR Reflections -----
    // Directional Lights
	for	(uint i = 0; i < u_DirCount; i++)
	{
		float shadow = 0.0;
		int shadowIdx = int(u_DirLights[i].colorAndShadow.w);

		if (shadowIdx >= 0)
			shadow = calcShadow(u_DirShadowMaps[shadowIdx], fs_in.v_FragPosDirLightSpace[shadowIdx], shadowBias);
	
		Lo += calcDirLight(u_DirLights[i], N, V, shadow, ALBEDO, ROUGHNESS, METALLIC, F0, tm);
	}
    // Spot Ligts
	for (uint i = 0; i < u_SpotCount; i++)
	{
		float shadow = 0.0;
		int shadowIdx = int(u_SpotLights[i].powerAndShadow.y);

		if (shadowIdx >= 0)
			shadow = calcShadow(u_SpotShadowMaps[shadowIdx], fs_in.v_FragPosSpotLightSpace[shadowIdx], shadowBias);
		
		Lo += calcSpotLight(u_SpotLights[i], N, V, fs_in.v_FragPos, shadow, ALBEDO, ROUGHNESS, METALLIC, F0, tm);
	}
	// Point Lights Loop
	for (uint i = 0; i < u_PointCount; i++)
	{
		float shadow = 0.0;
		int shadowIdx = int(u_PointLights[i].shadow.x);

		if (shadowIdx >= 0)
		{
			float lightRange = u_PointLights[i].positionAndRange.w;
			shadow = calcPointShadow(u_PointShadowMaps[shadowIdx], fs_in.v_FragPos, u_PointLights[i].positionAndRange.xyz, lightRange, shadowBias);
		}

		Lo += calcPointLight(u_PointLights[i], N, V, fs_in.v_FragPos, shadow, ALBEDO, ROUGHNESS, METALLIC, F0, tm);
	}

	vec3 F = F_SchlickR(max(dot(N, V), 0.0), F0, ROUGHNESS);

    vec3 kS = F;
    vec3 kD = 1.0 - kS;
    kD *= 1.0 - METALLIC;

	// --- Diffuse IBL ---
	vec3 irradiance = texture(u_IrradianceMap, N).rgb;
    
    // Account for the points inside irradiance
    if (tm > 0.001)
    {
        vec3 irradianceBack = texture(u_IrradianceMap, -N).rgb;
        irradiance = mix(irradiance, irradianceBack, tm * 0.5);
    }

	vec3 diffuse = irradiance * ALBEDO;

	// --- Specular IBL ---
    vec3 R = reflect(-V, N); 
    const float MAX_REFLECTION_LOD = 4.0;
    vec3 prefilteredColor = textureLod(u_PrefilterMap, R, ROUGHNESS * MAX_REFLECTION_LOD).rgb;
	// Sample the BRDF LUT using the view angle and roughness
    vec2 envBRDF = texture(u_BrdfLut, vec2(max(dot(N, V), 0.0), ROUGHNESS)).rg;
    // F0 * Scale + Bias
    vec3 specular = prefilteredColor * (F0 * envBRDF.x + envBRDF.y);

    vec3 ambient = (kD * diffuse + specular) * AO;

	FragColor = vec4(ambient + Lo, 1.0);

    // FragColor = vec4(tm, 0.1, tm, 1.0);  // tm map
}



// ===== PBR MATERIAL REFLECTION HELPERS =====
vec3 calcDirLight(DirLightData light, vec3 N, vec3 V, float shadow, vec3 ALBEDO, float ROUGHNESS, float METALLIC, vec3 F0, float tm)
{
    vec3 L = normalize(-light.directionAndPower.xyz);
    vec3 H = normalize(V + L);
    vec3 radiance = light.colorAndShadow.rgb * light.directionAndPower.w;
    
    float NDF = NDF_GGXTR(N, H, ROUGHNESS);   
    float G   = G_Smith(N, V, L, ROUGHNESS);
	vec3  F   = F_SchlickR(max(dot(N, V), 0.0), F0, ROUGHNESS);
    
    vec3 kS = F;
    vec3 kD = vec3(1.0) - kS;
    kD *= 1.0 - METALLIC;	  
    
    vec3 numerator    = NDF * G * F; 
    float denominator = 4.0 * max(dot(N, V), 0.0) * max(dot(N, L), 0.0) + 0.0001; 
    vec3 specular     = numerator / denominator;
    
    float NdotLClamped = max(dot(N, L), 0.0);  // [ 0, +1]
    float NdotLWrap    = dot(N, L);            // [-1, +1]


    // Sample translucency LUT
    float diffuseWrap = NdotLClamped;
    if (tm > 0.001) 
    {
        float u = NdotLWrap * 0.5 + 0.5;
        diffuseWrap = texture(u_TransLut, vec2(u, tm)).r;
    }

    vec3 diffuseComp  = (kD * ALBEDO / PI) * diffuseWrap;
    vec3 specularComp = specular * NdotLClamped;

    // Back scattered light should ignore shadow maps
    float shadowFactor = 1.0 - shadow;
    if (tm > 0.001 && NdotLWrap < 0.0) 
    {
        shadowFactor = mix(shadowFactor, 1.0, tm);
    }

    return (diffuseComp * shadowFactor + specularComp * (1.0 - shadow)) * radiance;
}

vec3 calcSpotLight(SpotLightData light, vec3 N, vec3 V, vec3 fragPos, float shadow, vec3 ALBEDO, float ROUGHNESS, float METALLIC, vec3 F0, float tm)
{
    vec3 L = normalize(light.positionAndLength.xyz - fragPos);
    vec3 H = normalize(V + L);
    
    float dist = length(light.positionAndLength.xyz - fragPos);
    float attenuation = 1.0 / (dist * dist);
    
    float theta = dot(L, normalize(-light.directionAndInner.xyz)); 
    float epsilon = light.directionAndInner.w - light.colorAndOuter.w; 
    float intensity = clamp((theta - light.colorAndOuter.w) / epsilon, 0.0, 1.0); 
    
    vec3 radiance = light.colorAndOuter.rgb * light.powerAndShadow.x * attenuation * intensity;
    
    float NDF = NDF_GGXTR(N, H, ROUGHNESS);   
    float G   = G_Smith(N, V, L, ROUGHNESS);      
    vec3  F   = F_SchlickR(max(dot(H, V), 0.0), F0, ROUGHNESS);
    
    vec3 kS = F;
    vec3 kD = vec3(1.0) - kS;
    kD *= 1.0 - METALLIC;	  
    
    vec3 numerator    = NDF * G * F; 
    float denominator = 4.0 * max(dot(N, V), 0.0) * max(dot(N, L), 0.0) + 0.0001; 
    vec3 specular     = numerator / denominator;

    float NdotLClamped = max(dot(N, L), 0.0);  // [ 0, +1]
    float NdotLWrap    = dot(N, L);            // [-1, +1]


    // Sample translucency LUT
    float diffuseWrap = NdotLClamped;
    if (tm > 0.001) 
    {
        float u = NdotLWrap * 0.5 + 0.5;
        diffuseWrap = texture(u_TransLut, vec2(u, tm)).r;
    }

    vec3 diffuseComp  = (kD * ALBEDO / PI) * diffuseWrap;
    vec3 specularComp = specular * NdotLClamped;

    // Back scattered light should ignore shadow maps
    float shadowFactor = 1.0 - shadow;
    if (tm > 0.001 && NdotLWrap < 0.0) 
    {
        shadowFactor = mix(shadowFactor, 1.0, tm);
    }

    return (diffuseComp * shadowFactor + specularComp * (1.0 - shadow)) * radiance;
}

vec3 calcPointLight(PointLightData light, vec3 N, vec3 V, vec3 fragPos, float shadow, vec3 ALBEDO, float ROUGHNESS, float METALLIC, vec3 F0, float tm)
{
    vec3 L = normalize(light.positionAndRange.xyz - fragPos);
    vec3 H = normalize(V + L);
    
    float dist = length(light.positionAndRange.xyz - fragPos);
    float attenuation = 1.0 / (dist * dist);
    vec3 radiance = light.colorAndPower.rgb * light.colorAndPower.w * attenuation;

    float NDF = NDF_GGXTR(N, H, ROUGHNESS);   
    float G   = G_Smith(N, V, L, ROUGHNESS);      
    vec3  F   = F_SchlickR(max(dot(H, V), 0.0), F0, ROUGHNESS);
    
    vec3 kS = F;
    vec3 kD = vec3(1.0) - kS;
    kD *= 1.0 - METALLIC;	  
    
    vec3 numerator    = NDF * G * F; 
    float denominator = 4.0 * max(dot(N, V), 0.0) * max(dot(N, L), 0.0) + 0.0001; 
    vec3 specular     = numerator / denominator;

    float NdotLClamped = max(dot(N, L), 0.0);  // [ 0, +1]
    float NdotLWrap    = dot(N, L);            // [-1, +1]


    // Sample translucency LUT
    float diffuseWrap = NdotLClamped;
    if (tm > 0.001) 
    {
        float u = NdotLWrap * 0.5 + 0.5;
        diffuseWrap = texture(u_TransLut, vec2(u, tm)).r;
    }

    vec3 diffuseComp  = (kD * ALBEDO / PI) * diffuseWrap;
    vec3 specularComp = specular * NdotLClamped;

    // Back scattered light should ignore shadow maps
    float shadowFactor = 1.0 - shadow;
    if (tm > 0.001 && NdotLWrap < 0.0) 
    {
        shadowFactor = mix(shadowFactor, 1.0, tm);
    }

    return (diffuseComp * shadowFactor + specularComp * (1.0 - shadow)) * radiance;
}

// ===== COOK-TORRANCE BRDF HELPERS =====
float NDF_GGXTR(vec3 N, vec3 H, float roughness)
{
    float a  = roughness * roughness;
    float a2 = a * a;
    float NdotH = max(dot(N, H), 0.0);
    float NdotH2 = NdotH * NdotH;

    float nom   = a2;
    float denom = (NdotH2 * (a2 - 1.0) + 1.0);
    denom = PI * denom * denom;

    return nom / denom;
}

float G_SchlickGGX(float NdotV, float roughness)
{
	// For Direct Lighting, k_dir = (a + 1)^2 / 8
    float r = (roughness + 1.0);
    float k = (r * r) / 8.0;

    float nom   = NdotV;
    float denom = NdotV * (1.0 - k) + k;

    return nom / denom;
}

float G_Smith(vec3 N, vec3 V, vec3 L, float roughness)
{
    float NdotV = max(dot(N, V), 0.0);
    float NdotL = max(dot(N, L), 0.0);
    float ggx2 = G_SchlickGGX(NdotV, roughness);
    float ggx1 = G_SchlickGGX(NdotL, roughness);

    return ggx1 * ggx2;
}

vec3 F_Schlick(float cosTheta, vec3 F0)
{
    return F0 + (1.0 - F0) * pow(clamp(1.0 - cosTheta, 0.0, 1.0), 5.0);
}

vec3 F_SchlickR(float cosTheta, vec3 F0, float roughness)
{
    return F0 + (max(vec3(1.0 - roughness), F0) - F0) * pow(clamp(1.0 - cosTheta, 0.0, 1.0), 5.0);
}

// ===== SHADOW FACTOR HELPERS =====
float calcShadow(sampler2D shadowMap, vec4 fragPosLightSpace, float bias)
{
	vec3 projCoords = fragPosLightSpace.xyz / fragPosLightSpace.w;
	projCoords = projCoords * 0.5 + 0.5;
	
	if (projCoords.z > 1.0)
        return 0.0;

	float closestDepth = texture(shadowMap, projCoords.xy).r;
	float currentDepth = projCoords.z;

	return currentDepth - bias > closestDepth ? 1.0 : 0.0;
}

float calcPointShadow(samplerCube shadowMap, vec3 fragPos, vec3 lightPos, float farPlane, float bias)
{
    vec3 fragToLight = fragPos - lightPos;

    float closestDepth = texture(shadowMap, fragToLight).r;

    closestDepth *= farPlane;

    float currentDepth = length(fragToLight);

    return currentDepth - bias > closestDepth ? 1.0 : 0.0;
}