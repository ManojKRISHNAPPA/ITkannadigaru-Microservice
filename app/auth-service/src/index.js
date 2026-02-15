const express = require("express");
const bcrypt = require("bcrypt");
const jwt = require("jsonwebtoken");
const mysql = require("mysql2/promise");

const app = express();
app.use(express.json());

// Environment variables
const PORT = process.env.PORT || 3001;
const ENV = process.env.ENV || "dev";
const VERSION = process.env.VERSION || "local";
const SERVICE = "instaclone-auth";
const BUILD_TIME = process.env.BUILD_TIME || new Date().toISOString();

// Database configuration
const DB_CONFIG = {
  host: process.env.DB_HOST || "localhost",
  port: parseInt(process.env.DB_PORT) || 3306,
  user: process.env.DB_USER || "root",
  password: process.env.DB_PASSWORD || "",
  database: process.env.DB_NAME || "instaclone",
  waitForConnections: true,
  connectionLimit: 10,
  queueLimit: 0
};

// JWT configuration
const JWT_SECRET = process.env.JWT_SECRET || "dev-secret-change-in-production";
const JWT_EXPIRY = "24h"; // Access token expiry
const REFRESH_EXPIRY = "30d"; // Refresh token expiry
const BCRYPT_ROUNDS = 10;

// Database connection pool
let pool;

// Initialize database connection
async function initDatabase() {
  try {
    pool = mysql.createPool(DB_CONFIG);
    // Test connection
    const connection = await pool.getConnection();
    console.log(`✅ Database connected: ${DB_CONFIG.host}:${DB_CONFIG.port}/${DB_CONFIG.database}`);
    connection.release();
  } catch (error) {
    console.error("❌ Database connection failed:", error.message);
    process.exit(1);
  }
}

// Health endpoint (required for Kubernetes)
app.get("/health", async (req, res) => {
  try {
    // Check database connectivity
    if (pool) {
      await pool.query("SELECT 1");
    }
    res.status(200).send("ok");
  } catch (error) {
    console.error("Health check failed:", error);
    res.status(503).send("unhealthy");
  }
});

// Version endpoint (required for deployment verification)
app.get("/version", (req, res) => {
  res.status(200).json({
    service: SERVICE,
    version: VERSION,
    env: ENV,
    buildTime: BUILD_TIME
  });
});

// Register new user
app.post("/auth/register", async (req, res) => {
  try {
    const { username, email, password } = req.body;

    // Validation
    if (!username || !email || !password) {
      return res.status(400).json({
        error: "Missing required fields",
        required: ["username", "email", "password"]
      });
    }

    // Validate username format (alphanumeric, underscore, 3-50 chars)
    if (!/^[a-zA-Z0-9_]{3,50}$/.test(username)) {
      return res.status(400).json({
        error: "Invalid username format. Use 3-50 alphanumeric characters or underscores"
      });
    }

    // Validate email format
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
      return res.status(400).json({ error: "Invalid email format" });
    }

    // Validate password strength (min 6 chars)
    if (password.length < 6) {
      return res.status(400).json({ error: "Password must be at least 6 characters" });
    }

    // Hash password
    const passwordHash = await bcrypt.hash(password, BCRYPT_ROUNDS);

    // Insert user into database
    const [result] = await pool.query(
      "INSERT INTO users (username, email, password_hash) VALUES (?, ?, ?)",
      [username, email, passwordHash]
    );

    console.log(`✅ User registered: ${username} (ID: ${result.insertId})`);

    res.status(201).json({
      message: "User registered successfully",
      userId: result.insertId,
      username
    });
  } catch (error) {
    console.error("Register error:", error);

    // Handle duplicate entry errors
    if (error.code === "ER_DUP_ENTRY") {
      if (error.message.includes("username")) {
        return res.status(409).json({ error: "Username already exists" });
      } else if (error.message.includes("email")) {
        return res.status(409).json({ error: "Email already exists" });
      }
      return res.status(409).json({ error: "Username or email already exists" });
    }

    res.status(500).json({ error: "Internal server error" });
  }
});

// Login user
app.post("/auth/login", async (req, res) => {
  try {
    const { email, password } = req.body;

    // Validation
    if (!email || !password) {
      return res.status(400).json({ error: "Missing email or password" });
    }

    // Find user by email
    const [rows] = await pool.query(
      "SELECT id, username, email, password_hash FROM users WHERE email = ?",
      [email]
    );

    if (rows.length === 0) {
      return res.status(401).json({ error: "Invalid credentials" });
    }

    const user = rows[0];

    // Verify password
    const isValid = await bcrypt.compare(password, user.password_hash);
    if (!isValid) {
      return res.status(401).json({ error: "Invalid credentials" });
    }

    // Generate access token
    const token = jwt.sign(
      {
        userId: user.id,
        username: user.username,
        email: user.email
      },
      JWT_SECRET,
      { expiresIn: JWT_EXPIRY }
    );

    // Generate refresh token
    const refreshToken = jwt.sign(
      { userId: user.id },
      JWT_SECRET,
      { expiresIn: REFRESH_EXPIRY }
    );

    console.log(`✅ User logged in: ${user.username} (ID: ${user.id})`);

    res.status(200).json({
      message: "Login successful",
      token,
      refreshToken,
      user: {
        id: user.id,
        username: user.username,
        email: user.email
      }
    });
  } catch (error) {
    console.error("Login error:", error);
    res.status(500).json({ error: "Internal server error" });
  }
});

// Validate token
app.get("/auth/validate", async (req, res) => {
  try {
    const authHeader = req.headers.authorization;

    if (!authHeader || !authHeader.startsWith("Bearer ")) {
      return res.status(401).json({ error: "No token provided" });
    }

    const token = authHeader.replace("Bearer ", "");

    // Verify token
    const decoded = jwt.verify(token, JWT_SECRET);

    res.status(200).json({
      valid: true,
      userId: decoded.userId,
      username: decoded.username,
      email: decoded.email
    });
  } catch (error) {
    if (error.name === "TokenExpiredError") {
      return res.status(401).json({ error: "Token expired" });
    }
    if (error.name === "JsonWebTokenError") {
      return res.status(401).json({ error: "Invalid token" });
    }
    console.error("Validate error:", error);
    res.status(500).json({ error: "Internal server error" });
  }
});

// Refresh token
app.post("/auth/refresh", async (req, res) => {
  try {
    const { refreshToken } = req.body;

    if (!refreshToken) {
      return res.status(400).json({ error: "No refresh token provided" });
    }

    // Verify refresh token
    const decoded = jwt.verify(refreshToken, JWT_SECRET);

    // Get user data from database
    const [rows] = await pool.query(
      "SELECT id, username, email FROM users WHERE id = ?",
      [decoded.userId]
    );

    if (rows.length === 0) {
      return res.status(401).json({ error: "User not found" });
    }

    const user = rows[0];

    // Generate new access token
    const token = jwt.sign(
      {
        userId: user.id,
        username: user.username,
        email: user.email
      },
      JWT_SECRET,
      { expiresIn: JWT_EXPIRY }
    );

    // Generate new refresh token
    const newRefreshToken = jwt.sign(
      { userId: user.id },
      JWT_SECRET,
      { expiresIn: REFRESH_EXPIRY }
    );

    console.log(`✅ Token refreshed for user: ${user.username} (ID: ${user.id})`);

    res.status(200).json({
      message: "Token refreshed successfully",
      token,
      refreshToken: newRefreshToken
    });
  } catch (error) {
    if (error.name === "TokenExpiredError") {
      return res.status(401).json({ error: "Refresh token expired" });
    }
    if (error.name === "JsonWebTokenError") {
      return res.status(401).json({ error: "Invalid refresh token" });
    }
    console.error("Refresh error:", error);
    res.status(500).json({ error: "Internal server error" });
  }
});

// Start server
async function startServer() {
  try {
    await initDatabase();

    app.listen(PORT, () => {
      console.log(`✅ ${SERVICE} running on port ${PORT}`);
      console.log(`   Environment: ${ENV}`);
      console.log(`   Version: ${VERSION}`);
      console.log(`   Build Time: ${BUILD_TIME}`);
      console.log(`   Database: ${DB_CONFIG.host}:${DB_CONFIG.port}/${DB_CONFIG.database}`);
    });
  } catch (error) {
    console.error("Failed to start server:", error);
    process.exit(1);
  }
}

// Handle graceful shutdown
process.on("SIGTERM", async () => {
  console.log("SIGTERM received, closing server...");
  if (pool) {
    await pool.end();
  }
  process.exit(0);
});

process.on("SIGINT", async () => {
  console.log("SIGINT received, closing server...");
  if (pool) {
    await pool.end();
  }
  process.exit(0);
});

// Start the server
startServer();
