(() => {
  const localHost = location.hostname === 'localhost' || location.hostname === '127.0.0.1';
  if (!('serviceWorker' in navigator) || (location.protocol !== 'https:' && !localHost)) {
    return;
  }
  window.addEventListener('load', () => {
    navigator.serviceWorker.register('terminal_service_worker.js', { scope: './' });
  });
})();
