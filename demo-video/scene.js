const menuPanel = document.querySelector("#menu-panel");
const rows = [...menuPanel.querySelectorAll(".mode-row")];
const shadedRow = rows[0];
const wireRow = rows[1];
const cursor = document.querySelector("#cursor");
const sidebar = document.querySelector("#sidebar");

const paintY = document.querySelector("#paint").getBoundingClientRect().y + 12;
const wheelY = document.querySelector("#wheel").getBoundingClientRect().y + 12;

const pointer = { x: 686, y: 381 };
const clock = { time: 0 };
gsap.set(cursor, { x: pointer.x, y: pointer.y, scale: 1 });
gsap.set(menuPanel, { opacity: 0 });

const timeline = gsap.timeline({ paused: true });

for (const [time, x, y] of [
  [3, 107, paintY],
  [6, 593, 25],
  [7.2, 612, 83],
  [9.8, 593, 25],
  [10.7, 608, 60],
  [12.1, 101, wheelY],
  [14.3, 686, 381],
]) {
  timeline.to(
    pointer,
    { x, y, duration: 0.65, ease: "power2.inOut" },
    time - 0.65,
  );
  if (time < 14) {
    timeline.to(
      cursor,
      { scale: 0.85, duration: 0.1, yoyo: true, repeat: 1 },
      time,
    );
  }
}

function draw() {
  const t = clock.time;
  const wire = t >= 7.2 && t < 10.7;
  const material = t >= 3 && t < 12.1;
  const mesh = t >= 12.1;
  const menuOpen = (t >= 6 && t < 7.2) || (t >= 9.8 && t < 10.7);
  gsap.set(cursor, { x: pointer.x, y: pointer.y });
  gsap.set(menuPanel, { opacity: menuOpen ? 1 : 0 });
  sidebar.classList.toggle("material", material);
  sidebar.classList.toggle("mesh", mesh);
  shadedRow.classList.toggle("current", !wire);
  wireRow.classList.toggle("current", wire);
  shadedRow.classList.toggle("hovered", t >= 10.3 && t < 10.7);
  wireRow.classList.toggle("hovered", t >= 6.8 && t < 7.2);
}

timeline.to(
  clock,
  { time: 15, duration: 15, ease: "none", onUpdate: draw },
  0,
);
window.__timelines = { demo: timeline };
draw();
