# Ollama — local inference backend for codescan (replaces the Mac-only oMLX/MLX).
# CUDA acceleration across the Thelio's 2× NVIDIA GPUs (RTX 2080 Ti + 3080 Ti, ~23GB).
#
# Added 2026-07-07 (Einstein) — codescan's semantic index lost its model backend in
# the Mac→Thelio migration (oMLX is Apple-MLX, Mac-only). codescan wants an
# embedding model over an OpenAI-compatible API; Ollama serves exactly that.
#
# 2026-07-28: the model moved from bge-m3 to jina-code-embeddings:1.5b (better
# code-relevance oracle, 8192 context). This file kept pre-pulling bge-m3 for three
# weeks after nothing consumed it. Keep `loadModels` and the per-repo config.ini in
# agreement — a mismatch is invisible until you notice two models resident in VRAM.
#
# After `ixnay reify`:
#   - service `ollama.service` comes up on http://127.0.0.1:11434
#   - the embedding model is pulled automatically (loadModels)
#   - point each repo's .codescan/config.ini at it:
#         embedding_url=http://127.0.0.1:11434
#         embedding_model=jina-code-embeddings:1.5b
#   - verify GPU offload:  ollama ps   (should show a GPU), and `nvidia-smi` during an index.
#
# NOTE: `acceleration = "cuda"` pulls the CUDA build of ollama + CUDA libs — a sizeable
# first-time download. Needs allowUnfree (already set in this host's nixpkgs config).
{ inputs, system, ... }:
{
  services.ollama = {
    enable = true;
    # The local fork carries parallel embedding-runner support. Its locked path
    # input snapshots the exact source in flake.lock, so this remains pure and
    # only changes when that input is explicitly refreshed.
    package = inputs.ollama.packages.${system}.default;
    host = "127.0.0.1";           # localhost only (codescan is local). Expose to tailnet later if needed.
    port = 11434;
    # 2026-07-28: was `[ "bge-m3" ]`. Every one of the 110 indexed repos actually
    # uses jina-code-embeddings:1.5b, so this line was pre-pulling and pinning a
    # SECOND embedding model into VRAM that nothing consumed — 664 MB of GPU and a
    # competing llama-server process. Peter deleted the model by hand; without this
    # change the next activation would silently re-download it.
    loadModels = [ "jina-code-embeddings:1.5b" ];
    environmentVariables.OLLAMA_NUM_PARALLEL = "3";
  };

  # Ollama's llama-server logs every slot operation at INFO: a `slot release` /
  # `update_slots` / `[GIN]` triple per embedding request. Measured 2026-07-28 at
  # 1,571,322 lines/hour — 99.3% of ALL journal traffic on this host.
  #
  # That was harmless while journald was volatile. Enabling systemd-journal-flush
  # (2026-07-28, to restore persistent logs absent since 2022-09-06) routed it to
  # /var/log/journal on rpool — which lives on two 7200rpm WD101FZBX drives behind
  # a USB dock, running at 58°C. The audible half-second disk clicking was this.
  #
  # Rate-limit rather than silence: real errors and the forensic capability we just
  # regained are worth keeping. 200 messages per 30s is far above any genuine error
  # rate and far below this firehose.
  systemd.services.ollama.serviceConfig = {
    LogRateLimitIntervalSec = 30;
    LogRateLimitBurst = 200;
  };
}
