package fast_noise


Feature_Flag :: enum u32 {
	Scalar,
	x86,
	SSE,
	SSE2,
	SSE3,
	SSSE3,
	SSE41,
	SSE42,
	AVX,
	AVX2,
	AVX512_F,
	AVX512_VL,
	AVX512_DQ,
	AVX512_BW,
	ARM,
	NEON,
	AARCH64,
	WASM,
	MAX,
}


Feature_Set :: bit_set[Feature_Flag]

FEATURE_SET_SCALAR :: Feature_Set{.Scalar}
FEATURE_SET_SSE :: Feature_Set{.x86, .SSE}
FEATURE_SET_SSE2 :: Feature_Set{.x86, .SSE, .SSE2}
FEATURE_SET_SSE3 :: Feature_Set{.x86, .SSE, .SSE2, .SSE3}
FEATURE_SET_SSSE3 :: Feature_Set{.x86, .SSE, .SSE2, .SSE3, .SSSE3}
FEATURE_SET_SSE41 :: Feature_Set{.x86, .SSE, .SSE2, .SSE3, .SSSE3, .SSE41}
FEATURE_SET_SSE42 :: Feature_Set{.x86, .SSE, .SSE2, .SSE3, .SSSE3, .SSE41, .SSE42}
FEATURE_SET_AVX :: Feature_Set{.x86, .SSE, .SSE2, .SSE3, .SSSE3, .SSE41, .SSE42, .AVX}
FEATURE_SET_AVX2 :: Feature_Set{.x86, .SSE, .SSE2, .SSE3, .SSSE3, .SSE41, .SSE42, .AVX, .AVX2}
FEATURE_SET_AVX512 :: Feature_Set {
	.x86,
	.SSE,
	.SSE2,
	.SSE3,
	.SSSE3,
	.SSE41,
	.SSE42,
	.AVX,
	.AVX2,
	.AVX512_F,
	.AVX512_VL,
	.AVX512_DQ,
	.AVX512_BW,
}
FEATURE_SET_NEON :: Feature_Set{.ARM, .NEON}
FEATURE_SET_AARCH64 :: Feature_Set{.ARM, .NEON, .AARCH64}
FEATURE_SET_WASM :: Feature_Set{.WASM}
FEATURE_SET_MAX :: Feature_Set{.MAX}