#ifndef FLUTTER_GGUF_BRIDGE_H
#define FLUTTER_GGUF_BRIDGE_H

#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

#if defined(_WIN32)
#define FLUTTER_GGUF_API __declspec(dllexport)
#else
#define FLUTTER_GGUF_API __attribute__((visibility("default")))
#endif

typedef struct flutter_gguf_context flutter_gguf_context_t;

/**
 * Initialize backend (call once at app start).
 */
FLUTTER_GGUF_API void flutter_gguf_backend_init(void);

/**
 * Load GGUF model and initialize context.
 * Returns pointer to context on success, NULL on error.
 */
FLUTTER_GGUF_API flutter_gguf_context_t* flutter_gguf_load_model(
    const char* model_path,
    int32_t n_ctx,
    int32_t n_threads,
    int32_t n_gpu_layers
);

/**
 * Tokenize input text.
 * Returns number of tokens written or negative required length if buffer too small.
 */
FLUTTER_GGUF_API int32_t flutter_gguf_tokenize(
    flutter_gguf_context_t* ctx,
    const char* text,
    int32_t* out_tokens,
    int32_t max_tokens,
    bool add_special,
    bool parse_special
);

/**
 * Prepare and evaluate prompt in context, setting up sampler chain.
 * Returns 0 on success, negative on error.
 */
FLUTTER_GGUF_API int32_t flutter_gguf_prepare_prompt(
    flutter_gguf_context_t* ctx,
    const char* prompt,
    float temperature,
    float top_p,
    int32_t top_k,
    float penalty_repeat,
    float penalty_freq,
    float penalty_present,
    uint32_t seed
);

/**
 * Generate next token piece.
 * Writes UTF-8 piece into out_piece (null terminated).
 * Sets is_eog to true when EOS/EOT reached or max context hit.
 * Returns byte length of piece on success, 0 on completion, negative on error.
 */
FLUTTER_GGUF_API int32_t flutter_gguf_step_token(
    flutter_gguf_context_t* ctx,
    char* out_piece,
    int32_t out_piece_size,
    int32_t* out_token_id,
    bool* is_eog
);

/**
 * Signal stop to active generation loop.
 */
FLUTTER_GGUF_API void flutter_gguf_stop_generation(flutter_gguf_context_t* ctx);

/**
 * Apply chat template to a sequence of role/content message pairs.
 * Returns written length or negative required length if buffer too small.
 */
FLUTTER_GGUF_API int32_t flutter_gguf_apply_chat_template(
    flutter_gguf_context_t* ctx,
    const char** roles,
    const char** contents,
    int32_t n_msg,
    bool add_ass,
    char* out_buf,
    int32_t buf_size
);

/**
 * Get model description string.
 */
FLUTTER_GGUF_API int32_t flutter_gguf_get_model_desc(
    flutter_gguf_context_t* ctx,
    char* out_desc,
    int32_t desc_size
);

/**
 * Get model training context size.
 */
FLUTTER_GGUF_API int32_t flutter_gguf_get_n_ctx_train(flutter_gguf_context_t* ctx);

/**
 * Get model layer count.
 */
FLUTTER_GGUF_API int32_t flutter_gguf_get_n_layer(flutter_gguf_context_t* ctx);

/**
 * Free context, sampler, and model resources.
 */
FLUTTER_GGUF_API void flutter_gguf_free_context(flutter_gguf_context_t* ctx);

#ifdef __cplusplus
}
#endif

#endif // FLUTTER_GGUF_BRIDGE_H
