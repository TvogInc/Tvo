const menuButton = document.querySelector(".menu-toggle");
const navigation = document.querySelector(".site-nav");

menuButton.addEventListener("click", () => {
  const isExpanded = menuButton.getAttribute("aria-expanded") === "true";
  menuButton.setAttribute("aria-expanded", String(!isExpanded));
  navigation.classList.toggle("is-open", !isExpanded);
});

navigation.addEventListener("click", (event) => {
  if (event.target.closest("a")) {
    menuButton.setAttribute("aria-expanded", "false");
    navigation.classList.remove("is-open");
  }
});

const revealElements = document.querySelectorAll(".reveal");
if ("IntersectionObserver" in window) {
  const revealObserver = new IntersectionObserver((entries, observer) => {
    for (const entry of entries) {
      if (entry.isIntersecting) {
        entry.target.classList.add("is-visible");
        observer.unobserve(entry.target);
      }
    }
  }, { threshold: 0.12 });
  revealElements.forEach((element) => revealObserver.observe(element));
} else {
  revealElements.forEach((element) => element.classList.add("is-visible"));
}

const downloadLink = document.querySelector(".release-download");
const downloadLabel = downloadLink.querySelector(".download-label");
const downloadHint = document.querySelector(".download-hint");

function configureReleaseDownload() {
  const configuredRepository = document.querySelector('meta[name="github-repository"]')?.content.trim();
  const pagesMatch = location.hostname.match(/^([^.]+)\.github\.io$/);
  const pathParts = location.pathname.split("/").filter(Boolean);
  const inferredRepository = pagesMatch
    ? `${pagesMatch[1]}/${pathParts[0] || `${pagesMatch[1]}.github.io`}`
    : null;
  const repository = configuredRepository || inferredRepository;

  if (!repository || !/^[\w.-]+\/[\w.-]+$/.test(repository)) {
    return;
  }

  downloadLink.href = `https://github.com/${repository}/releases/latest/download/Tvo.ipa`;
  downloadLink.classList.add("is-live");
  downloadLabel.textContent = "Download Tvo for iPhone";
  downloadHint.textContent = "Unsigned IPA · Sign and install with Sideloadly. GitHub Releases opens in a new tab.";
  downloadLink.target = "_blank";
  downloadLink.rel = "noopener noreferrer";
}

configureReleaseDownload();
