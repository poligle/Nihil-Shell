# nilo.nix by poligle
#
# Nilo: an optional assistant in the shell, with a local model on Ollama.
# Off by default. With `nihil.nilo.enable` the system runs Ollama on
# 127.0.0.1 and the shell gets Nilo (SUPER+I, the Copilot key, "?" in the
# launcher). The model, what Nilo may do and how long it stays awake are
# chosen in the shell and need no rebuild; this file decides whether it
# exists, what runs the model and that Nilo may start Ollama when it is down.

{ config, lib, pkgs, ... }:
let
    cfg = config.nihil.nilo;

    packages =
    {
        cpu = pkgs.ollama-cpu;
        vulkan = pkgs.ollama-vulkan;
        rocm = pkgs.ollama-rocm;
        cuda = pkgs.ollama-cuda;
    };

    modelType = lib.types.submodule
    {
        options =
        {
            tag = lib.mkOption
            {
                type = lib.types.str;
                example = "qwen3.5:9b";
                description = "Model name on ollama.com/library.";
            };
            label = lib.mkOption
            {
                type = lib.types.str;
                description = "Name shown in the shell.";
            };
            size = lib.mkOption
            {
                type = lib.types.number;
                description = "Download size in GB.";
            };
            ram = lib.mkOption
            {
                type = lib.types.number;
                description = ''
                    Memory it takes once loaded, in GB, roughly. The shell recommends
                    the largest model that fits in 45 % of the RAM.
                '';
            };
        };
    };
in
{
    options.nihil.nilo =
    {
        enable = lib.mkEnableOption "Nilo, the shell's assistant, with a local model on Ollama";

        acceleration = lib.mkOption
        {
            type = lib.types.enum [ "cpu" "vulkan" "rocm" "cuda" ];
            default = "cpu";
            example = "vulkan";
            description = ''
                What runs the model: the CPU, or the GPU through Vulkan (AMD, Intel,
                NVIDIA), ROCm (AMD) or CUDA (NVIDIA).
            '';
        };

        integratedGpu = lib.mkOption
        {
            type = lib.types.bool;
            default = false;
            description = ''
                Let Ollama use an integrated GPU, like the Radeon of a Ryzen laptop
                with `acceleration = "vulkan"`. Ollama leaves them out unless told
                (`OLLAMA_IGPU_ENABLE`), since a weak one can be slower than the CPU.
            '';
        };

        models = lib.mkOption
        {
            type = lib.types.listOf modelType;
            # Download sizes from ollama.com/library/qwen3.5 (default tags);
            # memory is an estimate with Nilo's context.
            default =
            [
                { tag = "qwen3.5:0.8b"; label = "Qwen 3.5 · 0.8B"; size = 1.3; ram = 2; }
                { tag = "qwen3.5:2b"; label = "Qwen 3.5 · 2B"; size = 2.7; ram = 3.5; }
                { tag = "qwen3.5:4b"; label = "Qwen 3.5 · 4B"; size = 3.4; ram = 5; }
                { tag = "qwen3.5:9b"; label = "Qwen 3.5 · 9B"; size = 6.6; ram = 8.5; }
                { tag = "qwen3.5:35b-a3b"; label = "Qwen 3.5 · 35B-A3B"; size = 22; ram = 25; }
            ];
            description = ''
                Models offered in Nilo's settings. Any model on ollama.com/library
                that supports tools works; others installed with `ollama pull` show
                up too.
            '';
        };

        contextLength = lib.mkOption
        {
            type = lib.types.ints.between 2048 262144;
            default = 16384;
            description = "Context window Nilo asks for, in tokens: more remembers more and takes more memory.";
        };

        searxng = lib.mkOption
        {
            type = lib.types.nullOr lib.types.str;
            default = null;
            example = "http://127.0.0.1:8888";
            description = ''
                A SearXNG instance (with the JSON format enabled) for Nilo's web
                searches. By default it searches DuckDuckGo through ddgr.
            '';
        };
    };

    config = lib.mkIf cfg.enable
    {
        services.ollama =
        {
            enable = true;
            package = packages.${cfg.acceleration};
            environmentVariables = lib.mapAttrs (_: lib.mkDefault) (
            {
                # Nilo sends its own keep-alive (its settings); this one is for
                # everything else that talks to Ollama.
                OLLAMA_KEEP_ALIVE = "5m";
                # One model in memory at a time: switching models frees the old one.
                OLLAMA_MAX_LOADED_MODELS = "1";
                # Local only: no models that run on ollama.com.
                OLLAMA_NO_CLOUD = "1";
            }
            // lib.optionalAttrs cfg.integratedGpu { OLLAMA_IGPU_ENABLE = "1"; });
        };

        # The upstream unit has no Restart=: if Ollama stops on its own (a
        # crash, the GPU not ready yet at boot) it stays down, and Nilo can
        # only say "connection refused". Back off up to a minute between tries.
        systemd.services.ollama.serviceConfig =
        {
            Restart = lib.mkDefault "on-failure";
            RestartSec = lib.mkDefault "2s";
            RestartSteps = lib.mkDefault 5;
            RestartMaxDelaySec = lib.mkDefault "1min";
        };

        # Nilo starts Ollama when it finds it stopped (and with its "start
        # ollama" button): polkit lets wheel users start or restart this one
        # unit without a password. Nothing else about systemd changes.
        security.polkit.enable = lib.mkDefault true;
        security.polkit.extraConfig = ''
            polkit.addRule(function(action, subject)
            {
                if (action.id == "org.freedesktop.systemd1.manage-units"
                    && action.lookup("unit") == "ollama.service"
                    && (action.lookup("verb") == "start" || action.lookup("verb") == "restart")
                    && subject.isInGroup("wheel"))
                    return polkit.Result.YES;
            });
        '';
    };
}
