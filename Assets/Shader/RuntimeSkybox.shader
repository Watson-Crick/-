Shader "AtmosphericScattering/RuntimeSkybox"
{
    SubShader
    {
        Tags { "Queue" = "Background" "RenderType" = "Background" "RenderPipeline" = "UniversalPipeline" "PreviewType" = "Skybox" }
        ZWrite Off Cull Off
        
        Pass
        {
            HLSLPROGRAM
            
            #pragma target 5.0
            
            #pragma vertex vert
            #pragma fragment frag
            
            #define _RENDERSUN 1
            
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "ShaderLibrary/InScattering.hlsl"
            
            #define SAMPLECOUNT_KSYBOX 64
            
            struct appdata
            {
                float3 vertex: POSITION;
            };
            
            struct v2f
            {
                float4 positionCS: SV_POSITION;
                float3 positionOS: TEXCOORD0;
            };
            
            v2f vert(appdata v)
            {
                v2f o;
                o.positionCS = TransformObjectToHClip(v.vertex);
                o.positionOS = v.vertex;
                return o;
            }
            
            half4 frag(v2f i): SV_Target
            {
                float3 rayStart = _WorldSpaceCameraPos.xyz;
                float3 rayDir = normalize(TransformObjectToWorld(i.positionOS));
                float3 planetCenter = float3(0, -_PlanetRadius, 0);
                float3 lightDir = _MainLightPosition.xyz;
                
                // 求视线与大气层交点, 即发生散射的位置
                float2 intersection = RaySphereIntersection(rayStart, rayDir, planetCenter, _PlanetRadius + _AtmosphereHeight);
                float rayLength = intersection.y;

                // 求视线与星球交点
                intersection = RaySphereIntersection(rayStart, rayDir, planetCenter, _PlanetRadius);
                // 这里离x是射线与球相交的反方向的店,y是射线与球相交的正方向的点
                if (intersection.x > 0)
                    rayLength = min(rayLength, intersection.x); // 视线与行星相交则用视点到行星的长度
                
                float3 extinction;

                // 计算天空盒经历散射后的颜色
                float3 inscattering = IntegrateInscattering(rayStart, rayDir, rayLength, planetCenter, 1, lightDir, SAMPLECOUNT_KSYBOX, extinction);
                return float4(inscattering, 1);
            }
            ENDHLSL
            
        }
    }
}
