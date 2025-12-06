const mono = 'ui-monospace, "SF Mono", SFMono-Regular, Menlo, monospace';

function getIAQStatus(iaq) {
  if (iaq <= 50) return { label: "Excellent", color: "#4ade80" };
  if (iaq <= 100) return { label: "Good", color: "#a3e635" };
  if (iaq <= 150) return { label: "Moderate", color: "#fbbf24" };
  if (iaq <= 200) return { label: "Poor", color: "#fb923c" };
  if (iaq <= 300) return { label: "Bad", color: "#f87171" };
  return { label: "Hazardous", color: "#ef4444" };
}

function setText(id, value) {
  const el = document.getElementById(id);
  if (!el) return;
  el.textContent = value;
}

async function fetchMetrics() {
  const res = await fetch("/api/metrics", { cache: "no-store" });
  if (!res.ok) throw new Error(`Request failed: ${res.status}`);
  return res.json();
}

async function fetchAltitude() {
  const res = await fetch("/api/altitude", { cache: "no-store" });
  if (!res.ok) throw new Error(`Request failed: ${res.status}`);
  return res.json();
}

function render(metrics) {
  const iaqStatus = getIAQStatus(metrics.iaq || 0);
  setText("iaq-value", Math.round(metrics.iaq || 0));
  const iaqLabel = document.getElementById("iaq-label");
  iaqLabel.textContent = iaqStatus.label;
  iaqLabel.style.color = iaqStatus.color;
  setText(
    "iaq-accuracy",
    `${metrics.accuracy_label || "stabilizing"} accuracy`,
  );

  setText("temp", (metrics.temperature_c || 0).toFixed(1));
  setText("humidity", (metrics.humidity_pct || 0).toFixed(1));
  setText("co2", Math.round(metrics.co2_ppm || 0));
  setText("voc", (metrics.voc_ppm || 0).toFixed(2));
  setText("pressure", (metrics.pressure_hpa || 0).toFixed(0));
  setText(
    "bsec-version",
    `${metrics.bsec_version.major}.${metrics.bsec_version.minor}.${metrics.bsec_version.major_bugfix}.${metrics.bsec_version.minor_bugfix}`,
  );
}

function renderAltitude(data) {
  if (data.error_message) {
    setText("altitude", "--");
    setText("altitude-meta", "unavailable");
    setText("pressure-meta", "sea level unavailable");
    return;
  }

  if (data.icao && data.observation_time) {
    const obsDate = new Date(data.observation_time);
    const obsTime = obsDate.toLocaleTimeString("en-GB", {
      hour: "2-digit",
      minute: "2-digit",
      timeZone: "UTC",
    });
    setText(
      "pressure-meta",
      `${data.icao} ${Math.round(data.altimeter_hpa || 0)} hPa • ${obsTime}Z`,
    );
  } else {
    setText(
      "pressure-meta",
      `sea level ${Math.round(data.altimeter_hpa || 0)} hPa`,
    );
  }

  setText("altitude", Math.round(data.relative_altitude || 0));

  if (data.icao && data.observation_time && data.updated_at) {
    const updDate = new Date(data.updated_at);

    const updTime = updDate.toLocaleTimeString("en-GB", {
      hour: "2-digit",
      minute: "2-digit",
      timeZone: "UTC",
    });

    setText("altitude-meta", `rel to ${data.icao} • upd ${updTime}Z`);
  } else {
    setText("altitude-meta", "relative to sea level");
  }
}

async function tick() {
  const error = document.getElementById("error");
  try {
    const [metrics, altitude] = await Promise.all([
      fetchMetrics(),
      fetchAltitude(),
    ]);
    render(metrics);
    renderAltitude(altitude);
    error.textContent = "";
  } catch (err) {
    error.textContent = `Unable to reach sensor API: ${err.message}`;
  }
}

setInterval(tick, 3000);
tick();
