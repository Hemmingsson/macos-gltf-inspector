#!/usr/bin/env node
// Render TestModels/References/Animated goldens with the pinned Khronos Sample Renderer.
//
//   ./scripts/fetch-test-models.sh
//   ./scripts/capture-khronos-animated-references.mjs
//
// Extracts the vendored page into .build/ (not committed) and drives headless Chrome.
// Writes only TestModels/References/Animated/*.png and fills a missing camera on
// Animated/manifest.json. Rest stills under TestModels/References/*.png are never opened
// for writing.
//
// Needs Google Chrome. Time must be > 0: the pinned AnimationTimer treats fixedTime 0 as unset.

import { spawn } from "node:child_process";
import { createHash } from "node:crypto";
import { createReadStream } from "node:fs";
import fs from "node:fs/promises";
import http from "node:http";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const animatedDir = path.join(root, "TestModels/References/Animated");
const manifestPath = path.join(animatedDir, "manifest.json");
const work = path.join(root, ".build/khronos-anim-capture");
const chrome = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";
const rendererCommit = "10201cb4746c0749125c0d7279b86985d1e84dfe";
const pageCommit = "f1fd1af";

const types = new Map([
    [".html", "text/html; charset=utf-8"],
    [".js", "text/javascript; charset=utf-8"],
    [".json", "application/json"],
    [".wasm", "application/wasm"],
    [".png", "image/png"],
    [".hdr", "application/octet-stream"],
    [".glb", "model/gltf-binary"],
    [".gltf", "model/gltf+json"],
    [".bin", "application/octet-stream"],
]);

function fail(message) {
    console.error(message);
    process.exit(1);
}

function pngPath(name) {
    if (name.includes("/") || name.includes("\\") || name.includes("..")) {
        fail(`refusing animated reference name ${name}`);
    }
    const file = path.resolve(animatedDir, `${name}.png`);
    if (!file.startsWith(animatedDir + path.sep)) fail(`refusing path ${file}`);
    return file;
}

function git(args) {
    return new Promise((resolve, reject) => {
        const child = spawn("git", args, { cwd: root });
        const stdout = [];
        const stderr = [];
        child.stdout.on("data", (chunk) => stdout.push(chunk));
        child.stderr.on("data", (chunk) => stderr.push(chunk));
        child.on("close", (code) => {
            if (code !== 0) {
                reject(new Error(Buffer.concat(stderr).toString() || `git ${args.join(" ")} failed`));
            } else {
                resolve(Buffer.concat(stdout));
            }
        });
    });
}

async function extractRenderer() {
    await fs.rm(work, { recursive: true, force: true });
    await fs.mkdir(path.join(work, "web"), { recursive: true });
    await new Promise((resolve, reject) => {
        const archive = spawn("git", ["archive", rendererCommit, "RendererWebKit/web-renderer"], { cwd: root });
        const unpack = spawn("tar", ["-x", "--strip-components=2", "-C", path.join(work, "web")]);
        archive.stdout.pipe(unpack.stdin);
        let err = "";
        archive.stderr.on("data", (chunk) => { err += chunk; });
        unpack.stderr.on("data", (chunk) => { err += chunk; });
        unpack.on("close", (code) => (code === 0 ? resolve() : reject(new Error(err || "extract failed"))));
        archive.on("close", (code) => { if (code !== 0) reject(new Error(err || "git archive failed")); });
    });
    const hdr = await git(["cat-file", "blob", `${rendererCommit}:assets/ibl/khronos/neutral.hdr`]);
    await fs.writeFile(path.join(work, "neutral.hdr"), hdr);
    await fs.copyFile(
        path.join(root, "scripts/khronos-animated-references/capture.html"),
        path.join(work, "web/capture.html"),
    );
    const bundle = path.join(work, "web/gltf-viewer.module.js");
    try {
        await fs.access(bundle);
    } catch {
        fail(`pinned Khronos bundle missing after extract (${rendererCommit}:RendererWebKit/web-renderer). Page source is ${pageCommit}.`);
    }
}

function startServer(jobs) {
    const samples = path.join(root, "TestModels/Khronos samples");
    const server = http.createServer(async (request, response) => {
        try {
            const url = new URL(request.url, "http://127.0.0.1");
            if (url.pathname === "/job") {
                const job = jobs.get(url.searchParams.get("name"));
                if (!job) {
                    response.writeHead(404);
                    response.end("unknown job");
                    return;
                }
                response.writeHead(200, { "Content-Type": "application/json" });
                response.end(JSON.stringify(job));
                return;
            }
            if (url.pathname === "/result" && request.method === "POST") {
                const chunks = [];
                for await (const chunk of request) chunks.push(chunk);
                const body = JSON.parse(Buffer.concat(chunks).toString());
                response.writeHead(204);
                response.end();
                server.emit("captured", body);
                return;
            }
            const file = resolveStatic(url.pathname, samples);
            if (!file) {
                response.writeHead(404);
                response.end("not found");
                return;
            }
            const type = types.get(path.extname(file)) ?? "application/octet-stream";
            response.writeHead(200, { "Content-Type": type });
            createReadStream(file).pipe(response);
        } catch (error) {
            response.writeHead(500);
            response.end(String(error));
        }
    });
    return new Promise((resolve) => {
        server.listen(0, "127.0.0.1", () => resolve(server));
    });
}

function resolveStatic(pathname, samples) {
    const decoded = decodeURIComponent(pathname);
    if (decoded === "/neutral.hdr") return path.join(work, "neutral.hdr");
    let rootDir;
    let relative;
    if (decoded.startsWith("/web/")) {
        rootDir = path.join(work, "web");
        relative = decoded.slice("/web/".length);
    } else if (decoded.startsWith("/models/")) {
        rootDir = samples;
        relative = decoded.slice("/models/".length);
    } else {
        return null;
    }
    const file = path.resolve(rootDir, relative);
    if (!file.startsWith(rootDir + path.sep)) return null;
    return file;
}

function captureOne(server, name) {
    const port = server.address().port;
    const url = `http://127.0.0.1:${port}/web/capture.html?name=${encodeURIComponent(name)}`;
    return new Promise((resolve, reject) => {
        const profile = path.join(work, `chrome-${name}`);
        const chromeProcess = spawn(chrome, [
            "--headless=new",
            "--disable-gpu-sandbox",
            "--use-angle=metal",
            "--enable-webgl",
            "--ignore-gpu-blocklist",
            "--hide-scrollbars",
            "--mute-audio",
            "--no-first-run",
            "--no-default-browser-check",
            "--disable-background-timer-throttling",
            `--user-data-dir=${profile}`,
            "--window-size=512,512",
            url,
        ], { stdio: ["ignore", "pipe", "pipe"] });
        let stderr = "";
        let done = false;
        const finish = (callback) => {
            if (done) return;
            done = true;
            clearTimeout(timer);
            chromeProcess.kill("SIGKILL");
            callback();
        };
        const timer = setTimeout(() => {
            finish(() => reject(new Error(`Chrome timed out on ${name}\n${stderr.slice(-4000)}`)));
        }, 90_000);
        chromeProcess.stderr.on("data", (chunk) => { stderr += chunk; });
        server.once("captured", (body) => {
            finish(() => {
                if (!body.ok) reject(new Error(`${name}: ${body.message}\n${stderr.slice(-4000)}`));
                else resolve(body);
            });
        });
        chromeProcess.on("exit", () => {
            finish(() => reject(new Error(`Chrome exited before ${name} posted a frame\n${stderr.slice(-4000)}`)));
        });
    });
}

function writePNG(name, dataURL) {
    const match = /^data:image\/png;base64,(.+)$/.exec(dataURL ?? "");
    if (!match) fail(`${name}: page did not return a PNG`);
    return fs.writeFile(pngPath(name), Buffer.from(match[1], "base64"));
}

async function main() {
    try {
        await fs.access(chrome);
    } catch {
        fail(`Khronos web capture needs Google Chrome at ${chrome}`);
    }
    const manifest = JSON.parse(await fs.readFile(manifestPath, "utf8"));
    await extractRenderer();
    const jobs = new Map();
    for (const entry of manifest.entries) {
        const folder = entry.sample;
        const file = entry.files[0];
        const model = path.join(root, "TestModels/Khronos samples", folder, file);
        try {
            await fs.access(model);
        } catch {
            fail(`${entry.name}: model missing at ${model}. Run ./scripts/fetch-test-models.sh`);
        }
        jobs.set(entry.name, {
            modelURL: `/models/${encodeURIComponent(folder)}/${file.split("/").map(encodeURIComponent).join("/")}`,
            environmentURL: "/neutral.hdr",
            size: manifest.look.canvasSize,
            look: manifest.look,
            animation: entry.animation,
            camera: entry.camera ?? null,
            orbit: { azimuth: 25, elevation: -18 },
        });
    }
    const server = await startServer(jobs);
    try {
        const hashes = [];
        for (const entry of manifest.entries) {
            process.stderr.write(`capturing ${entry.name}\n`);
            const result = await captureOne(server, entry.name);
            if (result.opaque < 100) {
                fail(`${entry.name}: posed frame is empty (${result.opaque} opaque pixels). renderer=${result.renderer}`);
            }
            const posed = createHash("sha256").update(result.png).digest("hex");
            const rest = createHash("sha256").update(result.restPng).digest("hex");
            if (posed === rest) {
                fail(`${entry.name}: posed frame matches rest, so the clip did not affect the Khronos still. renderer=${result.renderer}`);
            }
            await writePNG(entry.name, result.png);
            if (!entry.camera) {
                entry.camera = result.camera;
                console.log(`${entry.name} camera recorded from Khronos fit + orbit`);
            }
            hashes.push(posed);
            console.log(`${entry.name}: opaque ${result.opaque}, rest opaque ${result.restOpaque}, ${result.renderer}`);
        }
        const morph = manifest.entries.filter((entry) => entry.sample === "AnimatedMorphCube");
        if (morph.length >= 2 && hashes[0] === hashes[1]) {
            fail("AnimatedMorphCube times produced identical Khronos frames");
        }
        await fs.writeFile(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`);
        console.log(`wrote ${manifest.entries.length} PNGs under ${animatedDir}`);
    } finally {
        await new Promise((resolve) => server.close(resolve));
    }
}

main().catch((error) => fail(error.stack || String(error)));
