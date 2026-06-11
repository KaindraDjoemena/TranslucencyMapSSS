// main.cpp

#include <bolero.hpp>

#include "opaque.hpp"  // light pass
#include "passes/dir_shadow.hpp"  // shadow pass
#include "passes/spot_shadow.hpp"
#include "passes/point_shadow.hpp"
#include "passes/ibl_setup.hpp"
#include "passes/irradiance.hpp"
#include "passes/prefilter.hpp"
#include "passes/brdf_lut.hpp"
// #include "passes/post.hpp"
// #include "passes/ui.hpp"

#include "translucency_lut.hpp"
#include "post.hpp"
#include "ui.hpp"

#include <cmath>
#include <filesystem>

#include <iostream>

namespace blrc = blr::core;
namespace blra = blr::app;

// Force GPU usage
#ifdef _WIN32
    extern "C"
    {
        __declspec(dllexport) uint32_t NvOptimusEnablement = 1;
        
        __declspec(dllexport) int AmdPowerXpressRequestHighPerformance = 1;
    }
#endif

#define XSTR(s) STR(s)
#define STR(s) #s

#ifdef SANDBOX_ROOT_DIR
    const std::string ROOT_DIR = XSTR(SANDBOX_ROOT_DIR);
#else
    const std::string ROOT_DIR = "";
#endif

constexpr int         DEFAULT_WINDOW_WIDTH  = 1280;
constexpr int         DEFAULT_WINDOW_HEIGHT = 720;
constexpr const char* DEFAULT_WINDOW_TITLE  = "Bolero: Renderer";

float deltaTime = 0.0f;	
float lastFrame = 0.0f;


int main()
{
    std::filesystem::current_path("..");


    blra::Input input;
    blra::Window window(DEFAULT_WINDOW_WIDTH, DEFAULT_WINDOW_HEIGHT, DEFAULT_WINDOW_TITLE, input);
    window.AddResizeCallback([](uint32_t w, uint32_t h) {
            glViewport(0, 0, w, h);
        });
    
    blr::utils::PrintSystemInfo();

    blrc::Camera cam;
    cam.SetAspect((float)window.GetWidth() / (float)window.GetHeight());
    window.AddResizeCallback([&cam](uint32_t w, uint32_t h) {
            cam.SetAspect((float)w / (float)h);
        });
    input.AddMouseScrollCallback([&cam](double xOffset, double yOffset) {
            cam.OnScroll(yOffset);
        });
    input.AddMouseButtonCallback([&input, &cam](int button, int action, int mods) {
                if (button == blra::Input::MOUSE_BUTTON_MIDDLE)
                {
                    if (action == blra::Input::ACTION_PRESS)
                    {
                        cam.BeginDrag(glm::vec2(input.GetMouseX(), input.GetMouseY()), input.IsKeyDown(blra::Input::KEY_L_SHIFT));
                    }
                    else if (action == blra::Input::ACTION_RELEASE)
                    {
                        cam.EndDrag();
                    }
                }
            });

    
    blrc::AssetManager assetManager(ROOT_DIR);
    blrc::Scene        scene;
    scene.SetCam(&cam);
    

    // Model
    auto opaqueShader = assetManager.CreateShader(std::filesystem::path("src/light_pass_ss.glsl"));     // Modified shader
    auto dragon = assetManager.CreateModel(std::filesystem::path("src/models/Dragon.gltf"), opaqueShader);
    blrc::Transform transform;
    scene.AddEntity(dragon, transform);

    auto u_thicknessMap = assetManager.CreateTex("src/models/Dragon_Thickness.png");       // Raw thickness map

    if (!dragon->GetMeshes().empty()) 
    {
        auto mat = dragon->GetMeshes()[0]->GetMaterial();

        mat->SetAlbedoFactor(blrc::vec3(0.1f, 0.5f, 0.9f));
        mat->SetRoughnessFactor(0.25f);
        mat->SetMetallicFactor(0.0f);
    }


    blrc::Renderer::Init();
    blrc::RenderPipeline forward;

    window.AddResizeCallback([&forward](uint32_t w, uint32_t h) {
            forward.OnResize(w, h);
        });


    // Render pass context
    blrc::RenderContext renderCtx;

    // IBL Skybox Setup Pass
    auto hdrMap = assetManager.CreateTex("assets/hdri/newman_cafeteria_2k.hdr");
    auto eqToCubeShader = assetManager.CreateShader("assets/shaders/equirect_to_cubemap.glsl");
    blrc::Ref<IBLSetupPass> iblPass = std::make_shared<IBLSetupPass>(eqToCubeShader, hdrMap);

    // Scene Irradiance Pass
    auto convolutionShader = assetManager.CreateShader("assets/shaders/cubemap_convolution.glsl");
    blrc::Ref<IrradiancePass> irradiancePass = std::make_shared<IrradiancePass>(convolutionShader);
    
    // Environment Map Prefiltering Pass
    auto prefilterShader = assetManager.CreateShader("assets/shaders/prefilter.glsl");
    blrc::Ref<PrefilterPass> prefilterPass = std::make_shared<PrefilterPass>(prefilterShader);
    
    // BRDF LUT Pre Computation
    auto brdfLutShader = assetManager.CreateShader("assets/shaders/brdf_lut.glsl");
    blrc::Ref<BrdfLutPass> brdfLutPass = std::make_shared<BrdfLutPass>(assetManager, brdfLutShader);
    
    // Translucency LUT Pre Computation
    auto transLutShader = assetManager.CreateShader("src/translucency_lut.glsl");
    blrc::Ref<TransPass> transLutPass = std::make_shared<TransPass>(assetManager, transLutShader);

    // Scene Depth Pass (Shadow Mapping)
    auto depthShader      = assetManager.CreateShader("assets/shaders/shadow_pass.glsl");
    auto pointDepthShader = assetManager.CreateShader("assets/shaders/point_shadow_pass.glsl");
    blrc::Ref<DirShadowPass>   dirShadowPass   = std::make_shared<DirShadowPass>(depthShader);
    blrc::Ref<SpotShadowPass>  spotShadowPass  = std::make_shared<SpotShadowPass>(depthShader);
    blrc::Ref<PointShadowPass> pointShadowPass = std::make_shared<PointShadowPass>(pointDepthShader);
    
    // Opaque Pass (Skybox, Mesh)
    auto skyboxShader = assetManager.CreateShader("src/skybox.glsl");
    blrc::Ref<OpaquePass> opaquePass = std::make_shared<OpaquePass>(DEFAULT_WINDOW_WIDTH, DEFAULT_WINDOW_HEIGHT
                                                                   , opaqueShader, skyboxShader);
    // Post Process Pass
    auto postShader = assetManager.CreateShader("assets/shaders/post_pass.glsl");
    blrc::Ref<PostPass> postPass = std::make_shared<PostPass>(DEFAULT_WINDOW_WIDTH, DEFAULT_WINDOW_HEIGHT, postShader);
    
    // UI Pass
    blrc::Ref<UIPass> uiPass = std::make_shared<UIPass>(window.GetNativeWindow(), forward.GetPasses()
                                                       , opaqueShader, postShader);

    // Add Passes to the pipeline
    forward.AddPass(iblPass);
    forward.AddPass(irradiancePass);
    forward.AddPass(prefilterPass);
    forward.AddPass(brdfLutPass);
    forward.AddPass(transLutPass);
    forward.AddPass(dirShadowPass);
    forward.AddPass(spotShadowPass);
    forward.AddPass(pointShadowPass);
    forward.AddPass(opaquePass);
    forward.AddPass(postPass);
    forward.AddPass(uiPass);


    float hotReloadTimer = 0.0;
    while (!window.ShouldClose())
    {
        float currentFrame = static_cast<float>(glfwGetTime());
        deltaTime = currentFrame - lastFrame;
        lastFrame = currentFrame;

        hotReloadTimer += deltaTime;
        if (hotReloadTimer > 1.0f)
        {
            assetManager.Update();
            hotReloadTimer = 0.0f;
        }

        window.PollEvents();

        cam.HandleDrag(glm::vec2(input.GetMouseX(), input.GetMouseY()));

        blrc::Renderer::BeginFrame();
        
        scene.Update(deltaTime, true);

        renderCtx.Clear();

        renderCtx.SetTexture("u_ThicknessMap", u_thicknessMap->GetID());

        forward.Execute(scene, renderCtx);  // pass scene

        window.SwapBuffers();
    }

    blrc::Renderer::Shutdown();

    return 0;
}
