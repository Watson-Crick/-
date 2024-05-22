#ifndef _AC2_SCATTERING_INCLUDED
    #define _AC2_SCATTERING_INCLUDED
    
    // IntegrateInscattering
    // P - current integration point
    // A - camera position
    // C - top of the atmosphere
    #include "ACMath.hlsl"
    
    TEXTURE2D(_IntegralCPDensityLUT);
    SAMPLER(sampler_IntegralCPDensityLUT);
    
    uniform float2 _DensityScaleHeight;
    uniform float _PlanetRadius;
    uniform float _AtmosphereHeight;
    uniform float _SurfaceHeight;
    
    uniform float3 _ScatteringR;
    uniform float3 _ScatteringM;
    uniform float3 _ExtinctionR;
    uniform float3 _ExtinctionM;
    uniform float _MieG;
    
    uniform half3 _LightFromOuterSpace;
    uniform float _SunIntensity;
    uniform float _SunMieG;
    
    void ApplyPhaseFunction(inout float3 scatterR, inout float3 scatterM, float cosAngle)
    {
        scatterR *= RayleighPhase(cosAngle);
        scatterM *= MiePhaseHGCS(cosAngle, _MieG);
    }
    
    float3 RenderSun(float3 scatterM, float cosAngle)
    {
        return scatterM * MiePhaseHG(cosAngle, _SunMieG) * 0.003;
    }

    // 使用获取当前位置的粒子密度, 并用光照方向与当前到中心的夹角采样实现计算好的到太阳的粒子密度查找表
    void GetAtmosphereDensity(float3 position, float3 planetCenter, float3 lightDir, out float2 densityAtP, out float2 particleDensityCP)
    {
        // 这里是计算当前步进到的位置的密度与该位置到太阳的密度积分,参考图https://www.alanzucconi.com/2017/10/10/atmospheric-scattering-1/的每一步到太阳的密度积分,由于步进本身也是个循环所以这里单独计算不需要积分
        float height = length(position - planetCenter) - _PlanetRadius;
        densityAtP = ParticleDensity(height, _DensityScaleHeight.xy);
        
        float cosAngle = dot(normalize(position - planetCenter), lightDir.xyz);
        
        particleDensityCP = SAMPLE_TEXTURE2D_LOD(_IntegralCPDensityLUT, sampler_IntegralCPDensityLUT, float2(cosAngle * 0.5 + 0.5, (height / _AtmosphereHeight)), 0).xy;
    }

    void ComputeLocalInscattering(float2 densityAtP, float2 particleDensityCP, float2 particleDensityAP, out float3 localInscatterR, out float3 localInscatterM)
    {
        // c到a的密度
        float2 particleDensityCPA = particleDensityAP + particleDensityCP;

        // 计算散射的能量损耗, _ExtinctionR与_ExtinctionM分别是两个散射的散射系数
        float3 Tr = particleDensityCPA.x * _ExtinctionR;
        float3 Tm = particleDensityCPA.y * _ExtinctionM;
        float3 extinction = exp( - (Tr + Tm));

        // 计算a到p的步进散射系数, 最终用于叠加, 这里是用步进密度与透光度相乘,我们本质目的是计算摄像机到天空盒的可视终点的散射情况,所以这里只需要计算ap这条线上的即可
        localInscatterR = densityAtP.x * extinction;
        localInscatterM = densityAtP.y * extinction;
    }
    
    float3 IntegrateInscattering(float3 rayStart, float3 rayDir, float rayLength, float3 planetCenter, float distanceScale, float3 lightDir, float sampleCount, out float3 extinction)
    {
        rayLength *= distanceScale;
        float3 step = rayDir * (rayLength / sampleCount);
        float stepSize = length(step) ;//* distanceScale;
        
        // Rayleigh散射损耗系数
        float3 scatterR = 0;
        // Mie散射损耗系数
        float3 scatterM = 0;
        // 迭代用的间接参数, 存储临时的两个散射损耗系数, 上面两个系数也是步进叠加的
        float3 prevLocalInscatterR, prevLocalInscatterM;

        // 这是a到p点的某一段的粒子总量, 以下称步进密度
        float2 particleDensityAP = 0;
        // 两个迭代用的间接参数, 用于a到p的步进密度
        float2 densityAtP, prevDensityAtP;
        
        // c到p点的步进密度, 从_IntegralCPDensityLUT查找表上获取
        float2 particleDensityCP;

        // 瑞利散射由光照方向控制, 光照方向与星球相切则光到视点的长度最长, 被大气散射最严重, 所以蓝光被大量散射只剩下红光, 这也是夕阳偏红原因
        GetAtmosphereDensity(rayStart, planetCenter, lightDir, prevDensityAtP, particleDensityCP);
        // 计算散射损耗
        ComputeLocalInscattering(prevDensityAtP, particleDensityCP, particleDensityAP, prevLocalInscatterR, prevLocalInscatterM);
        
        // loop是正常进行for循环, 适用于较长的代码, 是有在执行循环该有的步骤, unroll是将代码展开写, 适用于较短的代码, 开销较小
        [loop]
        for (float s = 1.0; s < sampleCount; s += 1)
        {
            float3 p = rayStart + step * s;
            
            GetAtmosphereDensity(p, planetCenter, lightDir, densityAtP, particleDensityCP);
            particleDensityAP += (densityAtP + prevDensityAtP) * (stepSize / 2.0);
            
            prevDensityAtP = densityAtP;
            
            float3 localInscatterR, localInscatterM;
            ComputeLocalInscattering(densityAtP, particleDensityCP, particleDensityAP, localInscatterR, localInscatterM);
            
            scatterR += (localInscatterR + prevLocalInscatterR) * (stepSize / 2.0);
            scatterM += (localInscatterM + prevLocalInscatterM) * (stepSize / 2.0);
            
            prevLocalInscatterR = localInscatterR;
            prevLocalInscatterM = localInscatterM;
        }
        
        float3 m = scatterR;
        float cosAngle = dot(rayDir, lightDir.xyz);

        // 使用相位函数去真正处理两种散射
        ApplyPhaseFunction(scatterR, scatterM, cosAngle);
        
        float3 lightInscatter = (scatterR * _ScatteringR + scatterM * _ScatteringM) * _LightFromOuterSpace.xyz;
        #if defined(_RENDERSUN)
            lightInscatter += RenderSun(m, cosAngle) * _SunIntensity;
        #endif
        
        // Extinction
        extinction = exp( - (particleDensityAP.x * _ExtinctionR + particleDensityAP.y * _ExtinctionM));
        
        return lightInscatter.xyz;
    }
    
#endif