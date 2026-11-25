// Rebuild with SEECODE pointing to the installed seecode.mjs CLI.
import{execFileSync}from'node:child_process';
const cli=process.env.SEECODE ?? process.env.SEECODE_CLI;
if (!cli) throw new Error('Set SEECODE to the installed seecode.mjs path.');
execFileSync(process.execPath,[cli,'render','assets/docs/window-exploded.json'],{stdio:'inherit'});
execFileSync(process.execPath,[cli,'export','assets/docs/window-exploded.html','--formats','svg'],{stdio:'inherit'});

execFileSync('python3',['-c',`import importlib.util,pathlib;s=importlib.util.spec_from_file_location('style','assets/docs/style-diagrams.py');m=importlib.util.module_from_spec(s);s.loader.exec_module(m);p=pathlib.Path('assets/docs/window-exploded.svg');p.write_text(m.style_svg(p.read_text()))`]);
