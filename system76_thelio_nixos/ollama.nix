# Ollama — local inference backend for codescan (replaces the Mac-only oMLX/MLX).
# CUDA acceleration across the Thelio's 2× NVIDIA GPUs (RTX 2080 Ti + 3080 Ti, ~23GB).
#
# Added 2026-07-07 (Einstein) — codescan's semantic index lost its model backend in
# the Mac→Thelio migration (oMLX is Apple-MLX, Mac-only). codescan wants an
# embedding model over an OpenAI-compatible API; Ollama serves exactly that.
#
# 2026-07-28: the model moved from bge-m3 to jina-code-embeddings:1.5b (better
# code-relevance oracle, 8192 context). This file kept pre-pulling bge-m3 for three
# weeks after nothing consumed it.
#
# Models are NOT declared here. `loadModels` is deliberately empty; see the note
# beside it. The embedding model is a hand-modified local build that no registry
# can serve, and declaring models also creates a background downloader we do not
# want on this link. Install and update models with `ollama pull` / `ollama create`
# by hand, and keep each repo's config.ini pointed at whatever is actually resident.
#
# After `ixnay reify`:
#   - service `ollama.service` comes up on http://127.0.0.1:11434
#   - models are whatever was installed imperatively; verify with `ollama list`
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
    # Models on this host are managed IMPERATIVELY, on purpose. Leave this empty.
    #
    # 2026-07-28: this briefly listed jina-code-embeddings:1.5b and failed every
    # activation with `pull model manifest: file does not exist`. That model is a
    # local build whose metadata was modified by hand; it does not exist in any
    # registry, so `ollama pull` can never satisfy a declaration of it. The name
    # is resolvable only on this machine.
    #
    # An empty list is also what removes the downloader entirely: the nixpkgs
    # module generates ollama-model-loader.service under
    # `lib.mkIf (cfg.loadModels != [ ] || cfg.syncModels)`, so an empty list plus
    # syncModels=false means no unit is created and nothing downloads models in
    # the background. That is deliberate — embedding models are large enough that
    # an unattended pull can saturate this link when it is wanted elsewhere.
    #
    # DO NOT set `syncModels = true`. It deletes every installed model not named
    # here, which would destroy the customized jina build with no way to re-fetch
    # it. Keeping this list empty while syncModels is true would wipe everything.
    loadModels = [ ];
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
