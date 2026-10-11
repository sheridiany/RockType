# Voice worker dependencies

The worker statically links MLX Swift (`ml-explore/mlx-swift`, MIT), MLX Swift LM (`ml-explore/mlx-swift-lm`, MIT), and the speech-to-text portion of MLX Audio Swift (`Blaizzy/mlx-audio-swift`, MIT), with transitive packages pinned in `Package.resolved`.

The build copies upstream license/notice files from every resolved checkout into the XPC bundle's `Contents/Resources/ThirdPartyNotices`, retaining attribution for the distributed binary. The package lock records the exact source revisions. Model weights are downloaded separately at the user's request; their repositories are `mlx-community/Qwen3-ASR-0.6B-8bit` and `mlx-community/Qwen3-ASR-1.7B-8bit`, and are not distributed in the app.
