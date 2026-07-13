import "./gesture-test.css";

function required<T extends Element>(selector: string): T {
  const element = document.querySelector<T>(selector);
  if (!element) throw new Error(`测试页缺少元素：${selector}`);
  return element;
}

const pageNumber = required<HTMLElement>("#page-number");
const toast = required<HTMLElement>("#action-toast");

let currentPage = 1;
let toastTimer = 0;

function updatePage(delta: number): void {
  const nextPage = Math.max(1, Math.min(5, currentPage + delta));
  const direction = delta < 0 ? "上一页" : "下一页";
  currentPage = nextPage;
  pageNumber.textContent = String(currentPage);
  toast.textContent = `${direction} · 当前第 ${currentPage} 页`;
  toast.classList.add("is-visible");
  window.clearTimeout(toastTimer);
  toastTimer = window.setTimeout(() => toast.classList.remove("is-visible"), 1300);
}

window.addEventListener("keydown", (event) => {
  if (event.key === "ArrowLeft") updatePage(-1);
  if (event.key === "ArrowRight") updatePage(1);
});
