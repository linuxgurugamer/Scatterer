﻿
Shader "Scatterer/UnderwaterScatterDepthBuffer" {
	SubShader {
		Tags {"Queue" = "Transparent-499" "IgnoreProjector" = "True" "RenderType" = "Transparent"}

		Pass {
			Cull Off
			ZTest Off

			Blend SrcAlpha OneMinusSrcAlpha

			CGPROGRAM
			#pragma vertex vert
			#pragma fragment frag
			#pragma target 3.0
			#include "UnityCG.cginc"
			#include "../CommonAtmosphere.cginc"
			#include "../DepthCommon.cginc"

			uniform sampler2D ScattererScreenCopy;
			uniform sampler2D ScattererDepthCopy;
			float4x4 CameraToWorld;

			#pragma multi_compile DITHERING_OFF DITHERING_ON

			uniform float3 _planetPos;

			uniform float3 _Underwater_Color;

			uniform float transparencyDepth;
			uniform float darknessDepth;

			struct v2f
			{
				float4 screenPos : TEXCOORD0;
				float waterLightExtinction : TEXCOORD1;
			};

			v2f vert(appdata_base v, out float4 outpos: SV_POSITION)
			{
				v2f o;

		#if defined(SHADER_API_GLES) || defined(SHADER_API_GLES3) || defined(SHADER_API_GLCORE)
				outpos = float4(2.0 * v.vertex.x, 2.0 * v.vertex.y *_ProjectionParams.x, -1.0 , 1.0);
		#else
				outpos = float4(2.0 * v.vertex.x, 2.0 * v.vertex.y *_ProjectionParams.x, 0.0 , 1.0);
		#endif
				o.screenPos = ComputeScreenPos(outpos);

				float3 _camPos = _WorldSpaceCameraPos - _planetPos;
				o.waterLightExtinction = length(getSkyExtinction(normalize(_camPos + 10.0) * Rg , SUN_DIR));

				return o;
			}

			float3 oceanColor(float3 viewDir, float3 lightDir, float3 surfaceDir)
			{
				float angleToLightDir = (dot(viewDir, surfaceDir) + 1 )* 0.5;
				float3 waterColor = pow(_Underwater_Color, 4.0 *(-1.0 * angleToLightDir + 1.0));
				return waterColor;
			}

			struct fout
			{
				float4 color : COLOR;
				float depth : DEPTH;
			};

			fout frag(v2f i, UNITY_VPOS_TYPE screenPos : VPOS)
			{
				float2 uv = i.screenPos.xy / i.screenPos.w;

				uv.y = 1.0 - uv.y;
				float zdepth = tex2Dlod(ScattererDepthCopy, float4(uv,0,0));

				float3 invDepthWorldPos = getWorldPosFromDepth(i.screenPos.xy / i.screenPos.w, zdepth, CameraToWorld); //get the inaccurate worldPosition using the inverse projection method

				invDepthWorldPos = invDepthWorldPos - _WorldSpaceCameraPos.xyz;
				float invDepthLength = length(invDepthWorldPos);
				float3 worldViewDir = invDepthWorldPos / invDepthLength;

				//now refine the inaccurate distance
				//TODO: remove this from openGL
				float fragDistance = invDepthLength;
				if (fragDistance > 8000.0) //with this optimization 0.72 ms at KSC vs 0.87ms without, if I remove the refinement code completely takes 0.67 ms, I guess check what to do so you don't recompute the extinction, plus there is the horizon double sampling thing
				{
					fragDistance = getRefinedDistanceFromDepth(invDepthLength, zdepth, worldViewDir);
				}


				float3 _camPos = _WorldSpaceCameraPos - _planetPos;
				float underwaterDepth = Rg - length(_camPos);

				underwaterDepth = lerp(1.0,0.0,underwaterDepth / darknessDepth);

				float3 waterColor= underwaterDepth * hdrNoExposure(i.waterLightExtinction * _sunColor * oceanColor(worldViewDir,SUN_DIR,normalize(_camPos)));
				float alpha = min(fragDistance/transparencyDepth,1.0);

				float3 backGrnd = tex2Dlod(ScattererScreenCopy, float4(uv.x, uv.y,0.0,0.0));

				backGrnd = dither(waterColor, screenPos) * alpha + (1.0 - alpha) * backGrnd;

				fout output;
				output.color = float4(backGrnd,1.0);
				output.depth = zdepth;
				return output;
			}

			ENDCG
		}
	}
}