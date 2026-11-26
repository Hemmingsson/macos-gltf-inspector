import { execFileSync } from "node:child_process";
import { mkdir, mkdtemp, readdir, rename, rm } from "node:fs/promises";
import { existsSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";

const root = fileURLToPath(new URL(".", import.meta.url));
process.chdir(root);
const skillCli = join(root, "../.agents/skills/hyperframes/scripts/plugin-cli.mjs");
const localCli = join(root, "node_modules/.bin/hyperframes");
const runHyperframes = (args) => {
  if (existsSync(skillCli))
    execFileSync("node", [skillCli, ...args], { stdio: "inherit" });
  else execFileSync(localCli, args, { stdio: "inherit" });
};
const fps = 60;
const compositions = [
  ["index.html", "demo", 15],
  ["compositions/thumbnails.html", "finder-thumbnails", 4],
  ["compositions/quick-look.html", "quick-look", 3],
  ["compositions/preview-pane.html", "preview-pane", 3],
];
const requested = process.argv.slice(2);
for (const name of requested) {
  if (!compositions.some(([, output]) => output === name))
    throw Error("Unknown composition: " + name);
}
const scratch = await mkdtemp(join(tmpdir(), "gltf-hyperframes-"));
try {
  for (const [composition, name, seconds] of compositions) {
    if (requested.length && !requested.includes(name)) continue;
    const movie = join(scratch, name + ".mp4");
    runHyperframes([
      "render",
      ".",
      "-c",
      composition,
      "--quality",
      "looks",
      "--fps",
      String(fps),
      "-o",
      movie,
    ]);
    if (name === "demo") await rename(movie, join(root, "../docs/demo.mp4"));
    const framesDir = join(scratch, name + "-frames");
    await mkdir(framesDir, { recursive: true });
    execFileSync(
      "ffmpeg",
      [
        "-y",
        "-loglevel",
        "error",
        "-i",
        name === "demo" ? join(root, "../docs/demo.mp4") : movie,
        "-vf",
        `fps=${fps}`,
        join(framesDir, "f%04d.png"),
      ],
      { stdio: "inherit" },
    );
    const frames = (await readdir(framesDir))
      .filter((file) => file.endsWith(".png"))
      .sort();
    if (frames.length !== fps * seconds)
      throw Error(`Incomplete render of ${composition}: ${frames.length} frames`);
    const encoded = join(scratch, name + ".webp");
    const inputs = frames.flatMap((file, i) => [
      "-d",
      String(Math.round(((i + 1) * 1000) / fps) - Math.round((i * 1000) / fps)),
      join(framesDir, file),
    ]);
    execFileSync(
      "img2webp",
      [
        "-loop",
        "0",
        ...(name === "demo" ? ["-lossy", "-q", "77"] : ["-lossless"]),
        ...inputs,
        "-o",
        encoded,
      ],
      { stdio: "inherit" },
    );
    await rename(encoded, join(root, "../docs", name + ".webp"));
  }
} finally {
  await rm(scratch, { recursive: true, force: true });
}
