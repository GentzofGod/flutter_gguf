#include "flutter_gguf_bridge.h"
#include "llama.cpp/include/llama.h"

#include <vector>
#include <string>
#include <cstring>
#include <algorithm>
#include <atomic>
#include <iostream>
#include <cerrno>

#if defined(__ANDROID__)
#include <android/log.h>
#define LOG_TAG "FlutterGguf"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)
#define LOGW(...) __android_log_print(ANDROID_LOG_WARN, LOG_TAG, __VA_ARGS__)
#else
#define LOGI(...) printf(__VA_ARGS__); printf("\n")
#define LOGE(...) fprintf(stderr, __VA_ARGS__); fprintf(stderr, "\n")
#define LOGW(...) printf(__VA_ARGS__); printf("\n")
#endif

struct flutter_gguf_context {
    struct llama_model* model = nullptr;
    struct llama_context* ctx = nullptr;
    const struct llama_vocab* vocab = nullptr;
    struct llama_sampler* sampler = nullptr;
    int32_t n_past = 0;
    int32_t n_ctx = 2048;
    int32_t n_threads = 4;
    std::atomic<bool> is_generating{false};
    std::atomic<bool> should_stop{false};
};

static std::atomic<bool> g_backend_initialized{false};

static void flutter_gguf_log_callback(enum ggml_log_level level, const char * text, void * user_data) {
    (void)user_data;
    if (!text) return;
    if (level == GGML_LOG_LEVEL_ERROR) {
        LOGE("[llama.cpp] %s", text);
    } else if (level == GGML_LOG_LEVEL_WARN) {
        LOGW("[llama.cpp] %s", text);
    } else {
        LOGI("[llama.cpp] %s", text);
    }
}

FLUTTER_GGUF_API void flutter_gguf_backend_init(void) {
    if (!g_backend_initialized.exchange(true)) {
        llama_log_set(flutter_gguf_log_callback, nullptr);
        llama_backend_init();
        LOGI("llama backend initialized successfully");
    }
}

FLUTTER_GGUF_API flutter_gguf_context_t* flutter_gguf_load_model(
    const char* model_path,
    int32_t n_ctx,
    int32_t n_threads,
    int32_t n_gpu_layers
) {
    if (!model_path) {
        LOGE("Model path is null");
        return nullptr;
    }
    flutter_gguf_backend_init();

    LOGI("Loading model from path: %s (ctx: %d, threads: %d, gpu_layers: %d)",
         model_path, n_ctx, n_threads, n_gpu_layers);

    FILE* test_fp = fopen(model_path, "rb");
    if (!test_fp) {
        LOGE("Cannot fopen path '%s': %s (errno: %d)", model_path, strerror(errno), errno);
    } else {
        fseek(test_fp, 0, SEEK_END);
        long file_size = ftell(test_fp);
        LOGI("File '%s' accessible. Size: %ld bytes (%.2f MB)",
             model_path, file_size, (double)file_size / (1024.0 * 1024.0));
        fclose(test_fp);
    }

    struct llama_model_params model_params = llama_model_default_params();
    model_params.n_gpu_layers = n_gpu_layers;

    struct llama_model* model = llama_model_load_from_file(model_path, model_params);
    if (!model) {
        LOGW("llama_model_load_from_file failed on path: %s", model_path);
        return nullptr;
    }

    const struct llama_vocab* vocab = llama_model_get_vocab(model);
    if (!vocab) {
        LOGE("Failed to extract vocabulary from loaded model");
        llama_model_free(model);
        return nullptr;
    }

    struct llama_context_params ctx_params = llama_context_default_params();
    ctx_params.n_ctx = n_ctx > 0 ? (uint32_t)n_ctx : 2048;
    ctx_params.n_batch = 512;
    ctx_params.n_ubatch = 512;
    ctx_params.n_threads = n_threads > 0 ? n_threads : 4;
    ctx_params.n_threads_batch = n_threads > 0 ? n_threads : 4;

    struct llama_context* ctx = llama_init_from_model(model, ctx_params);
    if (!ctx) {
        LOGE("llama_init_from_model failed to create context");
        llama_model_free(model);
        return nullptr;
    }

    flutter_gguf_context_t* result = new flutter_gguf_context();
    result->model = model;
    result->ctx = ctx;
    result->vocab = vocab;
    result->sampler = nullptr;
    result->n_past = 0;
    result->n_ctx = (int32_t)llama_n_ctx(ctx);
    result->n_threads = ctx_params.n_threads;
    result->is_generating = false;
    result->should_stop = false;

    LOGI("Model loaded successfully! Actual n_ctx: %d", result->n_ctx);
    return result;
}

FLUTTER_GGUF_API int32_t flutter_gguf_tokenize(
    flutter_gguf_context_t* ctx,
    const char* text,
    int32_t* out_tokens,
    int32_t max_tokens,
    bool add_special,
    bool parse_special
) {
    if (!ctx || !ctx->vocab || !text) return -1;
    int32_t text_len = (int32_t)strlen(text);
    return llama_tokenize(ctx->vocab, text, text_len, out_tokens, max_tokens, add_special, parse_special);
}

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
) {
    if (!ctx || !ctx->ctx || !ctx->vocab || !prompt) return -1;

    // Reset KV cache memory
    llama_memory_t mem = llama_get_memory(ctx->ctx);
    if (mem) {
        llama_memory_clear(mem, true);
    }
    ctx->n_past = 0;
    ctx->should_stop = false;

    // Free existing sampler if any
    if (ctx->sampler) {
        llama_sampler_free(ctx->sampler);
        ctx->sampler = nullptr;
    }

    // Initialize sampler chain
    struct llama_sampler_chain_params sparams = llama_sampler_chain_default_params();
    ctx->sampler = llama_sampler_chain_init(sparams);

    int32_t n_vocab = llama_vocab_n_tokens(ctx->vocab);
    if (penalty_repeat > 1.0f || penalty_freq > 0.0f || penalty_present > 0.0f) {
        llama_sampler_chain_add(ctx->sampler, llama_sampler_init_penalties(n_vocab, 64, penalty_repeat, penalty_freq, penalty_present));
    }

    if (top_k > 0) {
        llama_sampler_chain_add(ctx->sampler, llama_sampler_init_top_k(top_k));
    }
    if (top_p > 0.0f && top_p < 1.0f) {
        llama_sampler_chain_add(ctx->sampler, llama_sampler_init_top_p(top_p, 1));
    }
    if (temperature > 0.0f) {
        llama_sampler_chain_add(ctx->sampler, llama_sampler_init_temp(temperature));
        llama_sampler_chain_add(ctx->sampler, llama_sampler_init_dist(seed == 0 ? LLAMA_DEFAULT_SEED : seed));
    } else {
        llama_sampler_chain_add(ctx->sampler, llama_sampler_init_greedy());
    }

    // Tokenize prompt
    int32_t prompt_len = (int32_t)strlen(prompt);
    int32_t n_tokens_alloc = prompt_len + 16;
    std::vector<llama_token> tokens(n_tokens_alloc);

    int32_t n_tokens = llama_tokenize(ctx->vocab, prompt, prompt_len, tokens.data(), n_tokens_alloc, true, true);
    if (n_tokens < 0) {
        n_tokens_alloc = -n_tokens;
        tokens.resize(n_tokens_alloc);
        n_tokens = llama_tokenize(ctx->vocab, prompt, prompt_len, tokens.data(), n_tokens_alloc, true, true);
        if (n_tokens < 0) {
            return -2; // Tokenization failed
        }
    }
    tokens.resize(n_tokens);

    if (tokens.empty()) {
        return -3; // Empty prompt
    }

    // Decode prompt tokens in batches
    int32_t batch_size = (int32_t)llama_n_batch(ctx->ctx);
    for (int32_t i = 0; i < n_tokens; i += batch_size) {
        int32_t chunk = std::min(batch_size, n_tokens - i);
        struct llama_batch batch = llama_batch_get_one(tokens.data() + i, chunk);
        int32_t ret = llama_decode(ctx->ctx, batch);
        if (ret != 0) {
            return -4; // Decode error
        }
    }

    ctx->n_past = n_tokens;
    ctx->is_generating = true;
    return 0;
}

FLUTTER_GGUF_API int32_t flutter_gguf_step_token(
    flutter_gguf_context_t* ctx,
    char* out_piece,
    int32_t out_piece_size,
    int32_t* out_token_id,
    bool* is_eog
) {
    if (!ctx || !ctx->ctx || !ctx->vocab || !ctx->sampler || !out_piece || !is_eog) {
        if (is_eog) *is_eog = true;
        return -1;
    }

    if (ctx->should_stop.load() || ctx->n_past >= ctx->n_ctx) {
        *is_eog = true;
        ctx->is_generating = false;
        out_piece[0] = '\0';
        return 0;
    }

    // Sample next token
    llama_token token = llama_sampler_sample(ctx->sampler, ctx->ctx, -1);
    if (out_token_id) {
        *out_token_id = token;
    }

    if (llama_vocab_is_eog(ctx->vocab, token)) {
        *is_eog = true;
        ctx->is_generating = false;
        out_piece[0] = '\0';
        return 0;
    }

    // Convert token to text piece
    int32_t piece_len = llama_token_to_piece(ctx->vocab, token, out_piece, out_piece_size - 1, 0, false);
    if (piece_len >= 0) {
        if (piece_len >= out_piece_size) {
            piece_len = out_piece_size - 1;
        }
        out_piece[piece_len] = '\0';
    } else {
        out_piece[0] = '\0';
        piece_len = 0;
    }

    // Accept token into sampler history
    llama_sampler_accept(ctx->sampler, token);

    // Decode this token for the next step
    struct llama_batch batch = llama_batch_get_one(&token, 1);
    int32_t ret = llama_decode(ctx->ctx, batch);
    if (ret != 0) {
        *is_eog = true;
        ctx->is_generating = false;
        return piece_len;
    }

    ctx->n_past++;
    *is_eog = false;
    return piece_len;
}

FLUTTER_GGUF_API void flutter_gguf_stop_generation(flutter_gguf_context_t* ctx) {
    if (ctx) {
        ctx->should_stop = true;
    }
}

FLUTTER_GGUF_API int32_t flutter_gguf_apply_chat_template(
    flutter_gguf_context_t* ctx,
    const char** roles,
    const char** contents,
    int32_t n_msg,
    bool add_ass,
    char* out_buf,
    int32_t buf_size
) {
    if (!ctx || !ctx->model || !roles || !contents || n_msg <= 0) return -1;

    const char* tmpl = llama_model_chat_template(ctx->model, nullptr);

    std::vector<struct llama_chat_message> chat(n_msg);
    for (int32_t i = 0; i < n_msg; ++i) {
        chat[i].role = roles[i];
        chat[i].content = contents[i];
    }

    return llama_chat_apply_template(tmpl, chat.data(), (size_t)n_msg, add_ass, out_buf, buf_size);
}

FLUTTER_GGUF_API int32_t flutter_gguf_get_model_desc(
    flutter_gguf_context_t* ctx,
    char* out_desc,
    int32_t desc_size
) {
    if (!ctx || !ctx->model || !out_desc) return -1;
    return llama_model_desc(ctx->model, out_desc, (size_t)desc_size);
}

FLUTTER_GGUF_API int32_t flutter_gguf_get_n_ctx_train(flutter_gguf_context_t* ctx) {
    if (!ctx || !ctx->model) return 0;
    return llama_model_n_ctx_train(ctx->model);
}

FLUTTER_GGUF_API int32_t flutter_gguf_get_n_layer(flutter_gguf_context_t* ctx) {
    if (!ctx || !ctx->model) return 0;
    return llama_model_n_layer(ctx->model);
}

FLUTTER_GGUF_API void flutter_gguf_free_context(flutter_gguf_context_t* ctx) {
    if (!ctx) return;

    ctx->should_stop = true;
    if (ctx->sampler) {
        llama_sampler_free(ctx->sampler);
        ctx->sampler = nullptr;
    }
    if (ctx->ctx) {
        llama_free(ctx->ctx);
        ctx->ctx = nullptr;
    }
    if (ctx->model) {
        llama_model_free(ctx->model);
        ctx->model = nullptr;
    }
    delete ctx;
}
