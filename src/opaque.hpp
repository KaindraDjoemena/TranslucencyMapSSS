#pragma once

#include <bolero.hpp>

namespace blrc = blr::core;

class OpaquePass : public blrc::RenderPass
{
public:
    OpaquePass(uint32_t initW, uint32_t initH, const blrc::Ref<blrc::Shader>& lightShader, const blrc::Ref<blrc::Shader>& skyboxShader)
    : RenderPass("Main Opaque Pass")
    , m_initW(initW)
    , m_initH(initH)
    , m_lightShader(lightShader)
    , m_skyboxShader(skyboxShader)
    {
    }

    void Init() override
    {
        m_fbo = blrc::FrameBuffer::Create({ m_initW, m_initH, { blrc::ImgFmt::RGBA16F, blrc::ImgFmt::Depth32F} });
    }

    void Execute(blrc::Scene& scene, blrc::RenderContext& renderCtx) override
    {
        m_fbo->Bind(); 

        glEnable(GL_DEPTH_TEST);
        glDepthFunc(GL_LESS);
        glEnable(GL_CULL_FACE);
        glCullFace(GL_BACK);
        
        glClearColor(0.0f, 0.0f, 0.0f, 1.0f);
        glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);

        blrc::Renderer::UpdateCameraUBO(*scene.GetCam());

        m_lightShader->Bind(); 

        // IBL Maps (Slots 5, 6, 7)
        glBindTextureUnit(5, renderCtx.GetTexture("u_IrradianceMap"));
        glBindTextureUnit(6, renderCtx.GetTexture("u_PrefilterMap"));
        glBindTextureUnit(7, renderCtx.GetTexture("u_BrdfLut"));
        
        glBindTextureUnit(8, renderCtx.GetTexture("u_ThicknessMap"));
        glBindTextureUnit(9, renderCtx.GetTexture("u_TransLut"));

        // Directional Shadows (Slots 10 - 13)
        int numDirShadows = renderCtx.GetInt("u_NumDirShadows"); 
        numDirShadows = std::min(numDirShadows, 4);
        for (int i = 0; i < numDirShadows; i++)
        {
            glBindTextureUnit(10 + i, renderCtx.GetTexture("u_DirDepthMapTex_" + std::to_string(i)));
            m_lightShader->SetMat4("u_DirLightSpaceMat[" + std::to_string(i) + "]", renderCtx.GetMat4("u_DirLightSpaceMat_" + std::to_string(i)));
        }
        // Spot Shadows (Slots 14 - 17)
        int numSpotShadows = renderCtx.GetInt("u_NumSpotShadows");
        numSpotShadows = std::min(numSpotShadows, 4);
        for (int i = 0; i < numSpotShadows; i++)
        {
            glBindTextureUnit(14 + i, renderCtx.GetTexture("u_SpotDepthMapTex_" + std::to_string(i)));
            m_lightShader->SetMat4("u_SpotLightSpaceMat[" + std::to_string(i) + "]", renderCtx.GetMat4("u_SpotLightSpaceMat_" + std::to_string(i)));
        }
        // Point Shadows (Slots 18 - 21)
        int numPointShadows = renderCtx.GetInt("u_NumPointShadows");
        numPointShadows = std::min(numPointShadows, 4);
        for (int i = 0; i < numPointShadows; i++)
        {
            glBindTextureUnit(18 + i, renderCtx.GetTexture("u_PointDepthMapTex_" + std::to_string(i)));
        }

        // Draw Opaque geometry
        blrc::Renderer::DrawQueue(blrc::RenderQueueType::OPAQUE, nullptr);

        // Draw Skybox
        glDepthFunc(GL_LEQUAL);

        m_skyboxShader->Bind();
        glBindTextureUnit(25, renderCtx.GetTexture("u_PrefilterMap"));
        blrc::Renderer::DrawCube();

        glDepthFunc(GL_LESS);

        m_fbo->Unbind();


        renderCtx.SetTexture("OPAQUE_PASS_TEX", m_fbo->GetColorAttachmentID(0));
    }

    virtual void OnResize(uint32_t width, uint32_t height) override
    {
        m_fbo->Resize(width, height);
    }

    void Shutdown() override {}

private:
    uint32_t m_initW;
    uint32_t m_initH;

    blrc::Ref<blrc::FrameBuffer> m_fbo;
    blrc::Ref<blrc::Shader> m_lightShader;
    blrc::Ref<blrc::Shader> m_skyboxShader;
};