const mono = 'ui-monospace, "SF Mono", SFMono-Regular, Menlo, monospace';

function getIAQStatus(iaq) {
  if (iaq <= 50) return { label: 'Excellent', color: '#4ade80' };
  if (iaq <= 100) return { label: 'Good', color: '#a3e635' };
  if (iaq <= 150) return { label: 'Moderate', color: '#fbbf24' };
  if (iaq <= 200) return { label: 'Poor', color: '#fb923c' };
  if (iaq <= 300) return { label: 'Bad', color: '#f87171' };
  return { label: 'Hazardous', color: '#ef4444' };
}

function setText(id, value) {
  const el = document.getElementById(id);
  if (!el) return;
  el.textContent = value;
}

async function fetchMetrics() {
  const res = await fetch('/api/metrics', { cache: 'no-store' });
  if (!res.ok) throw new Error(`Request failed: ${res.status}`);
  return res.json();
}

function render(metrics) {
  const iaqStatus = getIAQStatus(metrics.iaq || 0);
  setText('iaq-value', Math.round(metrics.iaq || 0));
  const iaqLabel = document.getElementById('iaq-label');
  iaqLabel.textContent = iaqStatus.label;
  iaqLabel.style.color = iaqStatus.color;
  setText('iaq-accuracy', `${metrics.accuracy_label || 'stabilizing'} accuracy`);

  setText('temp', (metrics.temperature_c || 0).toFixed(1));
  setText('humidity', (metrics.humidity_pct || 0).toFixed(1));
  setText('co2', Math.round(metrics.co2_ppm || 0));
  setText('voc', (metrics.voc_ppm || 0).toFixed(2));
  setText('pressure', (metrics.pressure_hpa || 0).toFixed(0));
  setText('bsec-version', `${metrics.bsec_version.major}.${metrics.bsec_version.minor}.${metrics.bsec_version.major_bugfix}.${metrics.bsec_version.minor_bugfix}`);
}

async function tick() {
  const error = document.getElementById('error');
  try {
    const data = await fetchMetrics();
    render(data);
    error.textContent = '';
  } catch (err) {
    error.textContent = `Unable to reach sensor API: ${err.message}`;
  }
}

setInterval(tick, 3000);
tick();