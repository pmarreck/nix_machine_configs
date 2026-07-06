# Ollama — local inference backend for codescan (replaces the Mac-only oMLX/MLX).
# CUDA acceleration across the Thelio's 2× NVIDIA GPUs (RTX 2080 Ti + 3080 Ti, ~23GB).
#
# Added 2026-07-07 (Einstein) — codescan's semantic index lost its model backend in
# the Mac→Thelio migration (oMLX is Apple-MLX, Mac-only). codescan wants a BGE-M3
# embedding model over an OpenAI-compatible API; Ollama serves exactly that.
#
# After `ixnay reify`:
#   - service `ollama.service` comes up on http://127.0.0.1:11434
#   - `bge-m3` is pulled automatically (loadModels)
#   - point each repo's .codescan/config.ini at it:
#         embedding_url=http://127.0.0.1:11434/v1
#         embedding_model=bge-m3
#         embedding_api=openai
#         embedding_dim=1024
#   - verify GPU offload:  ollama ps   (should show a GPU), and `nvidia-smi` during an index.
#
# NOTE: `acceleration = "cuda"` pulls the CUDA build of ollama + CUDA libs — a sizeable
# first-time download. Needs allowUnfree (already set in this host's nixpkgs config).
{ config, pkgs, ... }:
{
  services.ollama = {
    enable = true;
    package = pkgs.ollama-cuda;   # CUDA build for the 2× NVIDIA cards (replaces the deprecated acceleration="cuda")
    host = "127.0.0.1";           # localhost only (codescan is local). Expose to tailnet later if needed.
    port = 11434;
    loadModels = [ "bge-m3" ];    # codescan's embedding model — pre-pulled at activation
  };
}
