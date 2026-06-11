// skybox.glsl

#TYPE VERTEX
#version 460 core

const vec3 cubeVertices[36] = vec3[36](
    vec3(-1.0,  1.0, -1.0), vec3(-1.0, -1.0, -1.0), vec3( 1.0, -1.0, -1.0),
    vec3( 1.0, -1.0, -1.0), vec3( 1.0,  1.0, -1.0), vec3(-1.0,  1.0, -1.0),
    vec3(-1.0, -1.0,  1.0), vec3(-1.0, -1.0, -1.0), vec3(-1.0,  1.0, -1.0),
    vec3(-1.0,  1.0, -1.0), vec3(-1.0,  1.0,  1.0), vec3(-1.0, -1.0,  1.0),
    vec3( 1.0, -1.0, -1.0), vec3( 1.0, -1.0,  1.0), vec3( 1.0,  1.0,  1.0),
    vec3( 1.0,  1.0,  1.0), vec3( 1.0,  1.0, -1.0), vec3( 1.0, -1.0, -1.0),
    vec3(-1.0, -1.0,  1.0), vec3(-1.0,  1.0,  1.0), vec3( 1.0,  1.0,  1.0),
    vec3( 1.0,  1.0,  1.0), vec3( 1.0, -1.0,  1.0), vec3(-1.0, -1.0,  1.0),
    vec3(-1.0,  1.0, -1.0), vec3( 1.0,  1.0, -1.0), vec3( 1.0,  1.0,  1.0),
    vec3( 1.0,  1.0,  1.0), vec3(-1.0,  1.0,  1.0), vec3(-1.0,  1.0, -1.0),
    vec3(-1.0, -1.0, -1.0), vec3(-1.0, -1.0,  1.0), vec3( 1.0, -1.0, -1.0),
    vec3( 1.0, -1.0, -1.0), vec3(-1.0, -1.0,  1.0), vec3( 1.0, -1.0,  1.0)
);

layout(std140, binding = 0) uniform CameraBuffer
{
    mat4 u_View;
	mat4 u_Projection;
	vec4 u_CameraPosAndTime;
};

out vec3 v_TexCoords;

void main()
{
    v_TexCoords = cubeVertices[gl_VertexID];
    
    mat4 rotView = mat4(mat3(u_View)); 
    vec4 clipPos = u_Projection * rotView * vec4(v_TexCoords, 1.0);
    
    gl_Position = clipPos.xyww; 
}

#TYPE FRAGMENT
#version 460 core

out vec4 FragColor;
in vec3 v_TexCoords;

layout(binding = 25) uniform samplerCube u_PrefilterMap;

uniform float u_EnvironmentBlur = 0.95;

void main()
{
    vec3 envColor = textureLod(u_PrefilterMap, v_TexCoords, u_EnvironmentBlur).rgb;
    
	FragColor = vec4(envColor, 1.0);
}