// passes/ui.hpp

#pragma once

#include <bolero.hpp>
#include "ui/ui.hpp"

#include <imgui.h>
#include <imgui_impl_glfw.h>
#include <imgui_impl_opengl3.h>


namespace blrc = blr::core;

class UIPass : public blrc::RenderPass
{
public:
    UIPass(GLFWwindow* window, const std::vector<blrc::Ref<blrc::RenderPass>>& passes, const blrc::Ref<blrc::Shader>& activeShader, const blrc::Ref<blrc::Shader>& postShader)
    : RenderPass("UI Pass")
    , m_window(window)
    , m_passes(passes)
    , m_activeShader(activeShader)
    , m_postShader(postShader)
    {
    }

    void Init() override
    {
        m_ui.Init(m_window);


        if (m_activeShader)
        {
            m_activeShader->Bind();
            m_activeShader->SetBool("u_hasThicknessMap", m_hasThicknessMap);
        }

        if (m_postShader)
        {
            m_postShader->Bind();
            m_postShader->SetFloat("u_Exposure", m_Exposure);
        }
    }

    void Execute(blrc::Scene& scene, blrc::RenderContext& renderCtx) override
    {
        m_ui.BeginFrame();


        m_ui.DrawPipelineStats(scene, m_passes);

        
        if (ImGui::Begin("Scene"))
        {
            ImGui::Text("Camera Settings");
            ImGui::Separator();
            ImGui::Spacing();

            if (ImGui::SliderFloat("Exposure", &m_Exposure, 0.0f, 10.0f, "%.2f"))
            {
                if (m_postShader)
                {
                    m_postShader->Bind();
                    m_postShader->SetFloat("u_Exposure", m_Exposure);
                }
            }
        }
        ImGui::End();


        if (ImGui::Begin("Translucency"))
        {
            ImGui::Text("Thickness Map");
            ImGui::Separator();
            ImGui::Spacing();

            if (ImGui::Checkbox("On##Thickness", &m_hasThicknessMap))
            {
                if (m_activeShader)
                {
                    m_activeShader->Bind();
                    m_activeShader->SetBool("u_hasThicknessMap", m_hasThicknessMap);
                }
            }
        }
        ImGui::End();


        m_ui.EndFrame();
    }

    virtual void OnResize(uint32_t width, uint32_t height) override
    {
    }

    void Shutdown() override
    {
        m_ui.Shutdown();
    }

private:
    blrc::UI m_ui;

    GLFWwindow* m_window;
    const std::vector<blrc::Ref<RenderPass>>& m_passes;

    blrc::Ref<blrc::Shader> m_activeShader;
    bool m_hasThicknessMap = true;

    blrc::Ref<blrc::Shader> m_postShader;
    float m_Exposure = 1.0;
};