// translucency.glsl

#TYPE VERTEX
#version 460 core

out vec2 v_TexCoords;

void main()
{
    float x = -1.0 + float((gl_VertexID & 1) << 2);
    float y = -1.0 + float((gl_VertexID & 2) << 1);
    
    v_TexCoords.x = (x + 1.0) * 0.5;
    v_TexCoords.y = (y + 1.0) * 0.5;
    
    gl_Position = vec4(x, y, 0.0, 1.0);
}


#TYPE FRAGMENT
#version 460 core

in vec2 v_TexCoords;

out vec4 FragColor;

const float PI = 3.14159265359;


float IntegrateTranslucency(float texCoordU, float tm)
{
    // [0, 1] -> [-1, +1]
    float NdotL = 2.0 * texCoordU - 1.0;

    float theta = acos(NdotL);

    if (tm <= 0.001)
        return max(NdotL, 0.0);

    float translucencyMag = 0.0;
    float sumWeights = 0.0;

    const float STEP_SIZE = 0.025;
    for (float t = -PI; t <= PI; t += STEP_SIZE)
    {
        float weight = (1.0 / sqrt(2.0 * PI * tm)) * exp(-(t * t) / (2.0 * tm * tm));

        float sampleAngle = theta + t;

        float sampleDiffuse = max(cos(sampleAngle), 0.0);

        translucencyMag += sampleDiffuse * weight;
        sumWeights += weight;
    }

    return translucencyMag / sumWeights;
}

void main() 
{
    // X = Incident Angle (NdotL)
    // Y = Translucency Magnitude (tm)
    float integratedTranslucency = IntegrateTranslucency(v_TexCoords.x, v_TexCoords.y);

    FragColor = vec4(integratedTranslucency, 0.0 , 0.0, 1.0);
}