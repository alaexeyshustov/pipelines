require "capybara/rspec"
require "capybara/cuprite"

Capybara.javascript_driver = :cuprite
Capybara.default_max_wait_time = 5
Capybara.server = :webrick
# Not Capybara.disable_animation: its middleware injects an inline <script> into
# every response, which the enforced CSP blocks after Turbo body replacement.
# Instead inject the animation-off CSS in the browser before any page script.
module DisableAnimations
  SCRIPT = <<~JS.freeze
    document.addEventListener("DOMContentLoaded", function () {
      var style = document.createElement("style");
      style.textContent = "*, *::before, *::after { transition: none !important; animation: none !important; scroll-behavior: auto !important; caret-color: transparent !important; }";
      document.head.appendChild(style);
    });
  JS
end
