enum PlayerScript {
    // ponytail: YouTube's HTML player selectors; update here if its page structure changes.
    static let source = #"""
    (() => {
      if (!['www.youtube.com', 'youtube.com', 'm.youtube.com'].includes(location.hostname)) return;
      const settings = { volume: 0, background: false, repeatVideo: false };
      const video = () => document.querySelector('#movie_player video, video');
      const player = () => document.querySelector('#movie_player');
      const validID = id => typeof id === 'string' && /^[A-Za-z0-9_-]{11}$/.test(id);
      const enabled = button => !!button && !button.disabled && button.getAttribute('aria-disabled') !== 'true';
      function track(id, title) {
        return validID(id) ? { id, title: String(title || '').trim().slice(0, 512) } : null;
      }
      function currentTrack() {
        const data = player()?.getVideoData?.();
        return track(data?.video_id || new URL(location.href).searchParams.get('v'),
          data?.title || document.querySelector('h1.ytd-watch-metadata')?.textContent || document.title.replace(/ - YouTube$/, ''));
      }
      function nextTrack() {
        const button = document.querySelector('.ytp-next-button');
        if (!enabled(button)) return null;
        let id;
        try {
          const url = new URL(button.getAttribute('href'), location.href);
          if (url.protocol === 'https:' && ['www.youtube.com', 'youtube.com', 'm.youtube.com'].includes(url.hostname)) {
            id = url.searchParams.get('v');
          }
        } catch (_) {}
        if (!validID(id)) {
          try {
            const preview = new URL(button.dataset.preview);
            if (preview.protocol === 'https:' && preview.hostname === 'i.ytimg.com') id = preview.pathname.split('/')[2];
          } catch (_) {}
        }
        return track(id, button.dataset.tooltipText);
      }
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
      function applyRepeat() {
        const v = video();
        if (!v) return;
        const shouldLoop = settings.repeatVideo && !player()?.classList.contains('ad-showing')
          && !player()?.getVideoData?.()?.isLive && Number.isFinite(v.duration) && v.duration > 0;
        if (v.loop !== shouldLoop) v.loop = shouldLoop;
      }
      function apply() {
        document.documentElement.dataset.mdtBackground = String(settings.background);
        const v = video();
        if (v) {
          if (v.volume !== settings.volume) v.volume = settings.volume;
          if (v.muted !== (settings.volume === 0)) v.muted = settings.volume === 0;
        }
        configuredVideo = v;
        applyRepeat();
      }
      window.mornDesktopTube = {
        configure(next) { Object.assign(settings, next); apply(); return this.state(); },
        state() {
          const v = video();
          if (v && v !== configuredVideo) apply();
          const adPlaying = !!player()?.classList.contains('ad-showing');
          const isLive = !!player()?.getVideoData?.()?.isLive || v?.duration === Infinity;
          const duration = v && Number.isFinite(v.duration) && v.duration > 0 ? v.duration : null;
          return {
            hasVideo: !!v && v.readyState > 0, paused: !v || v.paused,
            volume: v ? (v.muted ? 0 : v.volume) : settings.volume,
            currentTime: v && Number.isFinite(v.currentTime) ? v.currentTime : 0,
            duration, isLive, adPlaying,
            canSeek: !!v && !!duration && v.seekable.length > 0 && !isLive && !adPlaying,
            currentTrack: currentTrack(), nextTrack: nextTrack(),
            canNext: !adPlaying && enabled(document.querySelector('.ytp-next-button')),
            canPrevious: !adPlaying && enabled(document.querySelector('.ytp-prev-button'))
          };
        },
        seek(seconds, expectedID) {
          const state = this.state();
          if (!Number.isFinite(seconds) || !state.canSeek || (state.currentTrack?.id || null) !== expectedID) {
            throw new Error('Video changed or cannot seek');
          }
          video().currentTime = Math.max(0, Math.min(state.duration, seconds));
          return this.state();
        },
        skip(direction) {
          const state = this.state();
          if ((direction === 1 && !state.canNext) || (direction === -1 && !state.canPrevious) || ![1, -1].includes(direction)) {
            throw new Error('No adjacent video');
          }
          document.querySelector(direction === 1 ? '.ytp-next-button' : '.ytp-prev-button').click();
          return this.state();
        },
        async togglePlayback() {
          const v = video();
          if (!v) throw new Error('No video');
          if (v.paused) await v.play(); else v.pause();
          return this.state();
        }
      };
      document.addEventListener('loadedmetadata', apply, true);
      document.addEventListener('durationchange', applyRepeat, true);
      document.addEventListener('volumechange', apply, true);
      document.addEventListener('yt-navigate-finish', apply);
      // Keep working when the dashboard is closed and YouTube replaces its player or starts an ad.
      new MutationObserver(applyRepeat).observe(document.documentElement, {
        subtree: true, childList: true, attributes: true, attributeFilter: ['class', 'loop']
      });
    })();
    """#
}
