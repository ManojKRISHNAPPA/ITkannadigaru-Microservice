import { useEffect, useState } from "react";

function Card({ title, children }) {
  return (
    <div
      style={{
        border: "1px solid #ddd",
        borderRadius: 12,
        padding: 16,
        marginTop: 12
      }}
    >
      <h3 style={{ margin: 0 }}>{title}</h3>
      <div style={{ marginTop: 8 }}>{children}</div>
    </div>
  );
}

export default function App() {
  const [health, setHealth] = useState("loading...");
  const [version, setVersion] = useState(null);
  const [info, setInfo] = useState(null);
  const [err, setErr] = useState("");

  async function load() {
    setErr("");

    // 1) Health (text)
    try {
      const h = await fetch("/api/health");
      const t = await h.text();
      setHealth(t);
    } catch (e) {
      setHealth("error");
      console.error("Health failed:", e);
      setErr((prev) => prev + " | health failed");
    }

    // 2) Version (json)
    try {
      const v = await fetch("/api/version");
      const t = await v.text(); // read as text first to avoid JSON parse crash
      setVersion(JSON.parse(t));
    } catch (e) {
      console.error("Version failed:", e);
      setErr((prev) => prev + " | version failed");
      setVersion(null);
    }

    // 3) Info (json)
    try {
      const i = await fetch("/api/info");
      const t = await i.text(); // read as text first to avoid JSON parse crash
      setInfo(JSON.parse(t));
    } catch (e) {
      console.error("Info failed:", e);
      setErr((prev) => prev + " | info failed");
      setInfo(null);
    }
  }

  useEffect(() => {
    load();
  }, []);

  return (
    <div style={{ fontFamily: "Arial, sans-serif", padding: 24, maxWidth: 900, margin: "0 auto" }}>
      <h2 style={{ marginBottom: 6 }}>DeployEcho</h2>
      <p style={{ marginTop: 0, color: "#555" }}>
        Simple release verification UI (env, version, pod-ish info).
      </p>

      <button
        onClick={load}
        style={{
          padding: "10px 14px",
          borderRadius: 10,
          border: "1px solid #ccc",
          background: "white",
          cursor: "pointer"
        }}
      >
        Refresh
      </button>

      {err && <p style={{ color: "red" }}>Error: {err}</p>}

      <Card title="Health">
        <div>
          <b>/health:</b> {health}
        </div>
      </Card>

      <Card title="Version">
        {!version ? (
          <div>Loading...</div>
        ) : (
          <pre style={{ margin: 0, whiteSpace: "pre-wrap" }}>{JSON.stringify(version, null, 2)}</pre>
        )}
      </Card>

      <Card title="Info">
        {!info ? (
          <div>Loading...</div>
        ) : (
          <pre style={{ margin: 0, whiteSpace: "pre-wrap" }}>{JSON.stringify(info, null, 2)}</pre>
        )}
      </Card>
    </div>
  );
}
