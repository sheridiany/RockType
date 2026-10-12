/* Progressive enhancement only: content and navigation remain available without JS. */
(() => {
  const toggle = document.querySelector(".menu-toggle");
  const navigation = document.querySelector("#navigation");
  const closeMenu = () => {
    navigation?.classList.remove("is-open");
    toggle?.setAttribute("aria-expanded", "false");
  };
  toggle?.addEventListener("click", () => {
    const open = toggle.getAttribute("aria-expanded") !== "true";
    toggle.setAttribute("aria-expanded", String(open));
    navigation.classList.toggle("is-open", open);
  });
  navigation?.addEventListener("click", (event) => {
    if (event.target.closest("a")) closeMenu();
  });
  document.addEventListener("keydown", (event) => {
    if (
      event.key === "Escape" &&
      toggle?.getAttribute("aria-expanded") === "true"
    ) {
      closeMenu();
      toggle.focus();
    }
  });
  const reduced = matchMedia("(prefers-reduced-motion: reduce)");
  if ("IntersectionObserver" in window) {
    const observer = new IntersectionObserver(
      (entries) =>
        entries.forEach((entry) => {
          if (entry.isIntersecting) {
            entry.target.classList.add("is-visible");
            observer.unobserve(entry.target);
          }
        }),
      { threshold: 0.06 },
    );
    if (!reduced.matches)
      document.querySelectorAll(".reveal").forEach((section) => {
        section.classList.add("reveal-ready");
        observer.observe(section);
      });
    reduced.addEventListener("change", () => {
      if (reduced.matches) {
        document
          .querySelectorAll(".reveal-ready")
          .forEach((section) => section.classList.add("is-visible"));
        observer.disconnect();
      }
    });
    const demo = document.querySelector(".voice-demo");
    if (demo) {
      new IntersectionObserver((entries) =>
        entries.forEach((entry) =>
          demo.classList.toggle("in-view", entry.isIntersecting),
        ),
      ).observe(demo);
      demo.addEventListener("click", () => {
        const playing = demo.dataset.playing !== "true";
        demo.dataset.playing = String(playing);
        demo.setAttribute("aria-pressed", String(playing));
        demo.setAttribute(
          "aria-label",
          playing ? "暂停波形演示" : "播放波形演示",
        );
      });
    }
  }
})();
