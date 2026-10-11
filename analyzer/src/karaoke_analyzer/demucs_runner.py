"""Run installed Demucs using cached weights only, with no implicit downloads."""
import os


def main():
    offline = os.environ.get("KARAOKE_OFFLINE_MODELS", "1") == "1"
    if offline:
        os.environ["HF_HUB_OFFLINE"] = "1"
    import torch
    from demucs.separate import main as separate

    def refuse_download(*args, **kwargs):
        raise RuntimeError(
            "Pesos do Demucs ausentes no cache. Autorize o download dos pesos oficiais "
            "na tela de importação ou prepare o cache antes de importar."
        )

    if offline:
        torch.hub.download_url_to_file = refuse_download
    separate()


if __name__ == "__main__":
    main()
