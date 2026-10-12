"""Summarize benchmark evidence without inventing ground truth for real music."""
import argparse
import json
from pathlib import Path


def region_coverage(notes, start, end):
    intervals = sorted((max(start, note["start"]),
                        min(end, note["start"] + note["duration"]))
                       for note in notes if note["start"] < end
                       and note["start"] + note["duration"] > start)
    merged = []
    for left, right in intervals:
        if merged and left <= merged[-1][1]:
            merged[-1][1] = max(merged[-1][1], right)
        else:
            merged.append([left, right])
    return sum(right - left for left, right in merged) / (end - start)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("root", type=Path)
    parser.add_argument("--plot", action="store_true", help="Save a standalone timing chart")
    args = parser.parse_args()
    results = []
    regions = []
    reported_regions = {"como_eu_quero": [(52, 57, "vocal"), (109, 115, "sem vocal")],
                        "amiga_da_minha_mulher": [(26, 28, "vocal"), (68, 70, "vocal")]}
    for path in sorted(args.root.glob("*/benchmark.json")):
        data = json.loads(path.read_text(encoding="utf-8"))
        data["run"] = path.parent.name
        results.append(data)
        if data.get("success"):
            name = Path(data["source"]).stem
            song = json.loads((path.parent / "song.json").read_text(encoding="utf-8"))
            for start, end, description in reported_regions.get(name, []):
                regions.append({"run": data["run"], "start": start, "end": end,
                                "user_reported": description,
                                "note_coverage": region_coverage(song["notes"], start, end),
                                "caution": "Coarse user report; pitch correctness not annotated"})
    sources = sorted({item["source"] for item in results})
    originals = [path for path in sources if not Path(path).is_relative_to(args.root.resolve())]
    comparisons = []
    for path in sorted(args.root.glob("*/comparison.json")):
        data = json.loads(path.read_text(encoding="utf-8"))
        data["run"] = path.parent.name
        comparisons.append(data)
    corpus = [{"source": path, "reviewed_annotations": None, "split": "unassigned",
               "tags": [], "review_status": "pending"} for path in originals]
    report = {"runs": results, "corpus": corpus, "comparisons": comparisons,
              "user_reported_regions": regions,
              "real_music_accuracy": None,
              "pending": ["20–30-song diverse corpus", "Human-reviewed notes/voicing",
                          "Held-out evaluation", "Peak RAM of subprocess tree and GPU memory",
                          "Cold/warm cache controlled comparisons", "Long-file stress cases"],
              "caution": "Note coverage is not pitch accuracy; confidence 1.0 is a placeholder."}
    (args.root / "summary.json").write_text(
        json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    lines = ["# Execução do plano de validação de pitch", "",
             "Métricas de precisão real pendentes: não há referência humana revisada.", "",
             "| Execução | Áudio (s) | Total (s) | pYIN 1/2 (s) | Demucs (s) | RTF | RAM pai (MiB) | Notas |",
             "| --- | ---: | ---: | --- | ---: | ---: | ---: | ---: |"]
    for item in results:
        if not item.get("success"):
            lines.append(f"| {item['run']} | FALHOU | {item.get('error', 'interrompido')} | | | | | |")
            continue
        stages = item["stages_seconds"]
        memory = item.get("peak_parent_memory_bytes")
        memory_text = f"{memory / 2**20:.0f}" if memory is not None else "não medido"
        lines.append(f"| {item['run']} | {item['duration_seconds']:.2f} | "
                     f"{item['total_seconds']:.2f} | {stages['estimate_pitch']:.2f} / "
                     f"{stages['estimate_secondary_pitch']:.2f} | "
                     f"{stages.get('separate_vocals', 0):.2f} | {item['rtf']:.3f} | "
                     f"{memory_text} | {item['note_count']} |")
    lines.extend(["", "## Trechos relatados pelo usuário", "",
                  "Cobertura temporal das notas; não comprova afinação. Os relatos são",
                  "anotações aproximadas de presença de vocal, não notas revisadas.", "",
                  "| Execução | Trecho (s) | Relato | Cobertura por notas |",
                  "| --- | --- | --- | ---: |"])
    for region in regions:
        lines.append(f"| {region['run']} | {region['start']}–{region['end']} | "
                     f"{region['user_reported']} | {100 * region['note_coverage']:.1f}% |")
    lines.extend(["", "## Comparação de estimadores", "",
                  "| Execução | Estimador | Tempo (s) | Notas (passagem única) |",
                  "| --- | --- | ---: | ---: |"])
    for comparison in comparisons:
        for row in comparison["results"]:
            if row["target_frequency"] is not None:
                continue
            seconds = row["seconds"]
            label = f"{seconds:.3f}" if seconds is not None else "diagnóstico pYIN reutilizado"
            lines.append(f"| {comparison['run']} | {row['backend']} | {label} | {row['notes']} |")
    lines.extend(["", "## Interpretação", "",
                  "RTF = tempo total / duração do áudio. RAM é o pico do processo Python pai;",
                  "não inclui FFmpeg/Demucs. O RTF inclui inicialização de cada processo.", "",
                  "As músicas originais e a biblioteca existente foram preservadas. Resultados",
                  "novos ficam em subpastas deste diretório. Tempos são observacionais: houve",
                  "testes/comparações simultâneos; não são benchmarks controlados de cache/carga.",
                  "A comparação usa segmentação de passagem única, sem consenso nem recuperação,",
                  "e não equivale ao pipeline de produção. Sem anotações, número e duração",
                  "das notas são diagnósticos e não validam a voz principal.", "",
                  "## Pendências", "", *[f"- {value}" for value in report["pending"]]])
    (args.root / "REPORT.md").write_text("\n".join(lines) + "\n", encoding="utf-8")
    if args.plot:
        import matplotlib
        matplotlib.use("Agg")
        import matplotlib.pyplot as plt
        valid = [item for item in results if item.get("success")]
        figure, axis = plt.subplots(figsize=(12, max(4, len(valid) * 0.45)))
        left = [0.0] * len(valid)
        for stage, label in [("decode_to_wav", "Decode"), ("separate_vocals", "Demucs"),
                             ("estimate_pitch", "pYIN 2048"),
                             ("estimate_secondary_pitch", "pYIN 4096")]:
            values = [item["stages_seconds"].get(stage, 0) for item in valid]
            axis.barh([item["run"] for item in valid], values, left=left, label=label)
            left = [a + b for a, b in zip(left, values)]
        axis.set_xlabel("Tempo observado (segundos)")
        axis.set_title("Custo por etapa — execuções observacionais, sem controle completo de carga")
        axis.legend()
        figure.tight_layout()
        figure.savefig(args.root / "timings.png", dpi=150)
        plt.close(figure)
    print(f"{len(results)} runs, {len(originals)} original sources; report: {args.root / 'REPORT.md'}")


if __name__ == "__main__":
    main()
