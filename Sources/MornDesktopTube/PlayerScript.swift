enum PlayerScript {
    // ponytail: YouTube's HTML player selectors; update here if its page structure changes.
    static let source = #"""
    (() => {
      if (!['www.youtube.com', 'youtube.com', 'm.youtube.com'].includes(location.hostname)) return;
      const settings = { volume: 0, background: false };
      const video = () => document.querySelector('#movie_player video, video');
      let configuredVideo = null;
      const style = document.createElement('style');
      style.textContent = `
        html[data-mdt-background="true"], html[data-mdt-background="true"] body {
          background: black !important; overflow: hidden !important;
        }
        html[data-mdt-background="true"] body * { visibility: hidden !important; }
        html[data-mdt-background="true"] body *:has(#movie_player) {
          transform: none !important; contain: none !important; overflow: visible !important;
        }
        html[data-mdt-background="true"] #movie_player,
        html[data-mdt-background="true"] #movie_player * { visibility: visible !important; }
        html[data-mdt-background="true"] #movie_player {
          position: fixed !important; inset: 0 !important;
          width: 100vw !important; height: 100vh !important; z-index: 2147483647 !important;
        }
        html[data-mdt-background="true"] #movie_player .html5-video-container {
          position: absolute !important; inset: 0 !important; width: 100% !important; height: 100% !important;
        }
        html[data-mdt-background="true"] #movie_player video {
          position: absolute !important; inset: 0 !important; width: 100% !important; height: 100% !important;
          object-fit: contain !important;
        }
      `;
      document.documentElement.appendChild(style);
      function apply() {
        document.documentElement.dataset.mdtBackground = String(settings.background);
        const v = video();
        if (v) {
          if (v.volume !== settings.volume) v.volume = settings.volume;
          if (v.muted !== (settings.volume === 0)) v.muted = settings.volume === 0;
        }
        configuredVideo = v;
      }
      window.mornDesktopTube = {
        configure(next) { Object.assign(settings, next); apply(); return this.state(); },
        state() {
          const v = video();
          if (v && v !== configuredVideo) apply();
          return { hasVideo: !!v && v.readyState > 0, paused: !v || v.paused, volume: v ? (v.muted ? 0 : v.volume) : settings.volume };
        },
        async togglePlayback() {
          const v = video();
          if (!v) throw new Error('No video');
          if (v.paused) await v.play(); else v.pause();
          return this.state();
        }
      };
      document.addEventListener('loadedmetadata', apply, true);
      document.addEventListener('volumechange', apply, true);
      document.addEventListener('yt-navigate-finish', apply);
    })();
    """#
}
