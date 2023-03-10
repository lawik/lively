// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import { Socket } from "phoenix"
import { LiveSocket } from "phoenix_live_view"
import topbar from "../vendor/topbar"

navigator.getUserMedia = navigator.getUserMedia ||
    navigator.webkitGetUserMedia ||
    navigator.mozGetUserMedia ||
    navigator.msGetUserMedia;

let hooks = {
    video: {
        mounted() {
            console.log("mounted")
            let video = this.el;
            var errorCallback = function (e) {
                console.log('Reeeejected!', e);
            };

            this.handleEvent("go-to-slide", ({ slide }) => {
                Reveal.slide(slide, 0, 0)
            })

            this.handleEvent("next-slide", () => {
                Reveal.right()
            })

            this.handleEvent("previous-slide", () => {
                Reveal.left()
            })

            // Not showing vendor prefixes.
            navigator.getUserMedia({ video: true, audio: false }, function (localMediaStream) {
                console.log(localMediaStream)
                //video.src = window.URL.createObjectURL(localMediaStream);
                video.srcObject = localMediaStream;
                console.log("set up")

                // Note: onloadedmetadata doesn't fire in Chrome when using it with getUserMedia.
                // See crbug.com/110938.
                video.onloadedmetadata = function (e) {
                    console.log("onloadedmetadata");
                    // Ready to go. Do some stuff.
                };
            }, errorCallback);

            // More info about initialization & config:
            // - https://revealjs.com/initialization/
            // - https://revealjs.com/config/
            Reveal.initialize({
                hash: true,
                center: false,
                embedded: true,
                controls: false,
                progress: false,
                width: "100%",
                height: "100%",

                // Learn about plugins: https://revealjs.com/plugins/
                plugins: [RevealMarkdown, RevealHighlight, RevealNotes]
            });
        }
    }
}

let csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
let liveSocket = new LiveSocket("/live", Socket, { params: { _csrf_token: csrfToken }, hooks: hooks })

// Show progress bar on live navigation and form submits
topbar.config({ barColors: { 0: "#29d" }, shadowColor: "rgba(0, 0, 0, .3)" })
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket
