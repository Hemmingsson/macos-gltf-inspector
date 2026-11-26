const composition = document.querySelector('main').dataset.compositionId;
const rows = document.querySelectorAll('.file');
const pointer = document.querySelector('.pointer');
const clock = {time: 0};
const timeline = gsap.timeline({paused: true});
const smooth = value => {
  const x = Math.max(0, Math.min(1, value));
  return x*x*(3 - 2*x);
};
function frame(el, n, columns, w, h) {
  el.style.backgroundPosition = -(n%columns)*w+'px '+(-Math.floor(n/columns)*h)+'px';
}
function draw() {
  const t = clock.time;
  let selection = 0, cursorY = 125;
  if (composition === 'quick-look') {
    const panel = document.querySelector('.quick-look');
    const open = smooth((t-.55)/.3) * smooth((4.55-t)/.3);
    panel.style.opacity = open;
    panel.style.transform = 'scale('+(.6+.4*open)+')';
    frame(panel, Math.min(45,Math.floor(Math.max(0,t-.65)*12)), 6,480,380);
  } else {
    const travel = smooth((t-.8)/.48) * smooth((4.18-t)/.48);
    cursorY += travel * 32;
    selection = t >= 1.28 && t < 4.18 ? 1 : 0;
    const model = document.querySelector('.model');
    model.classList.toggle('studio',selection === 1);
    if (selection === 0) {
      const modelTime = t < 1.28 ? t : Math.max(0, 5 - t);
      frame(model, Math.floor(modelTime * 12), 7, 220, 200);
    }
    else model.style.backgroundPosition = 'center';
    document.querySelector('aside h2').textContent = selection ? 'AET_Gen2.glb' : 'AET_Showcase.glb';
    document.querySelector('aside p').textContent = selection ? 'GL Transmission Format - Binary' : 'GL Transmission Format - Binary';
  }
  rows.forEach((row,i)=>row.classList.toggle('selected',i===selection));
  gsap.set(pointer, { x: 159, y: cursorY });
}
timeline.to(clock,{time:5,duration:5,ease:'none',onUpdate:draw},0);

gsap.set(pointer, { x: 159, y: 125 });
draw();
