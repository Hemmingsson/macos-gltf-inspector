// Offline WebGL filtering with the vendored pinned Khronos module.
// Usage: node bake-field.mjs <playwright-module> <source.hdr> <output.json>
import fs from 'node:fs';
const upstream = new URL('./upstream/', import.meta.url);
const [driver, source, output] = process.argv.slice(2);
if (!output) throw Error('Usage: node bake-field.mjs <playwright-module> <source.hdr> <output.json>');
const {chromium} = await import(driver);
const module = fs.readFileSync(new URL('gltf-viewer.module.js', upstream)).toString()
    + '\nexport {iblSampler, loadHDR};\n';
const browser = await chromium.launch({executablePath: '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome', headless: true,
    args: ['--use-angle=metal', '--disable-gpu-watchdog']});
try {
    const page = await browser.newPage();
    page.on('console', msg => console.error(msg.text()));
    await page.route('https://bake.invalid/**', route => {
        const path = new URL(route.request().url()).pathname;
        if (path === '/renderer.mjs') return route.fulfill({contentType: 'text/javascript', body: module});
        if (path === '/source.hdr') return route.fulfill({body: fs.readFileSync(source)});
        return route.fulfill({contentType: 'text/html', body: '<canvas></canvas>'});
    });
    await page.goto('https://bake.invalid/');
    const bake = await page.evaluate(async () => {
        const {GltfView, iblSampler, loadHDR} = await import('/renderer.mjs');
        const gl = document.querySelector('canvas').getContext('webgl2');
        if (!gl) throw Error('WebGL 2 unavailable');
        const view = new GltfView(gl);
        const sampler = new iblSampler(view);
        const image = await loadHDR(new Uint8Array(await (await fetch('/source.hdr')).arrayBuffer()));
        sampler.init(image);
        if (!sampler.supportedFormats.includes('HALF_FLOAT')) throw Error('Half float framebuffer unavailable');
        // Keep the existing shared BRDF LUTs; only the panorama-dependent cubes change.
        sampler.panoramaToCubeMap();
        sampler.cubeMapToLambertian();
        sampler.cubeMapToGGX();
        sampler.cubeMapToSheen();
        gl.finish();
        const textures = [];
        const framebuffer = gl.createFramebuffer();
        gl.bindFramebuffer(gl.FRAMEBUFFER, framebuffer);
        for (const [name, texture, maxMip] of [
            ['diffuse', sampler.lambertianTextureID, 0],
            ['specular', sampler.ggxTextureID, sampler.mipmapLevels],
            ['sheen', sampler.sheenTextureID, sampler.mipmapLevels],
        ]) {
            const levels = [];
            for (let mip = 0; mip <= maxMip; mip++) for (let face = 0; face < 6; face++) {
                const size = sampler.textureSize >> mip;
                gl.framebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_CUBE_MAP_POSITIVE_X + face, texture, mip);
                if (gl.checkFramebufferStatus(gl.FRAMEBUFFER) !== gl.FRAMEBUFFER_COMPLETE) throw Error('Incomplete framebuffer');
                const pixels = new Uint16Array(size * size * 4);
                gl.readPixels(0, 0, size, size, gl.RGBA, gl.HALF_FLOAT, pixels);
                if (gl.getError() !== gl.NO_ERROR) throw Error('Cube readback failed');
                let encoded = '';
                for (const byte of new Uint8Array(pixels.buffer)) encoded += String.fromCharCode(byte);
                levels.push({mip, face, width: size, height: size, data: btoa(encoded)});
            }
            textures.push({name, size: sampler.textureSize, cube: true, levels});
        }
        return {version: 1, upstream: '863b981', environment: 'field', intensityScale: sampler.scaleValue,
            mipCount: sampler.mipmapLevels, textures};
    });
    fs.writeFileSync(output, JSON.stringify(bake));
} finally { await browser.close(); }
