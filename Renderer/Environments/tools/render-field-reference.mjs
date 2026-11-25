// Independently render only the Field feature golden with the pinned Khronos renderer.
// Usage: node render-field-reference.mjs <playwright-module> <hdr> <output.png>
import fs from 'node:fs';
const upstream = new URL('./upstream/', import.meta.url);
const [driver, source, output] = process.argv.slice(2);
const {chromium} = await import(driver);
const module = fs.readFileSync(new URL('gltf-viewer.module.js', upstream));
const browser = await chromium.launch({executablePath: '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome', headless: true,
    args: ['--use-angle=metal', '--disable-gpu-watchdog']});
try {
    const page = await browser.newPage();
    page.on('console', msg => console.error(msg.text()));
    await page.route('https://bake.invalid/**', route => {
        const path = new URL(route.request().url()).pathname;
        if (path === '/renderer.mjs') return route.fulfill({contentType: 'text/javascript', body: module});
        if (path === '/source.hdr') return route.fulfill({body: fs.readFileSync(source)});
        if (path === '/model.glb') return route.fulfill({body: fs.readFileSync('TestModels/Khronos samples/BoomBox/BoomBox.glb')});
        if (path.startsWith('/libs/')) return route.fulfill({contentType: path.endsWith('.wasm') ? 'application/wasm' : 'text/javascript', body: fs.readFileSync(new URL('.' + path, upstream))});
        if (path.startsWith('/assets/')) return route.fulfill({body: fs.readFileSync(new URL('.' + path, upstream))});
        return route.fulfill({contentType: 'text/html', body: '<canvas width="256" height="256"></canvas>'});
    });
    await page.goto('https://bake.invalid/');
    const result = await page.evaluate(async () => {
        const {GltfView, GltfState, ResourceLoader} = await import('/renderer.mjs');
        const canvas = document.querySelector('canvas');
        const gl = canvas.getContext('webgl2', {preserveDrawingBuffer: true, alpha: true});
        const view = new GltfView(gl), state = view.createState(), resources = new ResourceLoader(view);
        const params = state.renderingParameters;
        params.toneMap = GltfState.ToneMaps.KHR_PBR_NEUTRAL;
        params.clearColor = [0,0,0,0]; params.renderEnvironmentMap = false;
        params.exposure = 1; params.environmentRotation = 90; params.iblIntensity = 1;
        state.environment = await resources.loadEnvironment('/source.hdr', {lut_sheen_E_file: '/assets/lut_sheen_E.png'});
        params.useIBL = true;
        state.gltf = await resources.loadGltf('/model.glb');
        state.sceneIndex = state.gltf.scene ?? 0; state.animationIndices = [];
        const camera = state.userCamera;
        camera.perspective.yfov = Math.PI/4; camera.perspective.aspectRatio = 1;
        camera.fitViewToScene(state.gltf, state.sceneIndex);
        const min = camera.sceneExtents.min, max = camera.sceneExtents.max;
        const target = min.map((v,i)=>(v+max[i])/2);
        // FeatureReferenceTests fits the front view using the shared 1.02-padded
        // projected-AABB distance, then orbits without re-fitting.
        const distance = (Math.max(max[0]-min[0], max[1]-min[1])/2/Math.tan(Math.PI/8)+(max[2]-min[2])/2)*1.02;
        camera.rotAroundY = Math.PI/6; camera.rotAroundX = -Math.PI/9;
        camera.setRotation(camera.rotAroundY,camera.rotAroundX);
        camera.setDistanceFromTarget(distance,target); camera.baseDistance = distance;
        view.renderFrame(state,256,256); view.renderFrame(state,256,256);
        const flattened = document.createElement('canvas'); flattened.width = flattened.height = 256;
        const ctx = flattened.getContext('2d'); ctx.fillStyle = 'rgb(128,128,128)'; ctx.fillRect(0,0,256,256); ctx.drawImage(canvas,0,0);
        return {png:flattened.toDataURL('image/png'), camera:{distance,target,yfov:camera.perspective.yfov,znear:camera.perspective.znear,zfar:camera.perspective.zfar}};
    });
    fs.writeFileSync(output,Buffer.from(result.png.split(',')[1],'base64'));
    console.log(JSON.stringify(result.camera));
} finally {await browser.close();}
