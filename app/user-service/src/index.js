const express = require("express");
const jwt = require("jsonwebtoken");
const mysql = require("mysql2/promise");
const multer = require("multer");
const { S3Client, PutObjectCommand, DeleteObjectCommand } = require("@aws-sdk/client-s3");
const crypto = require("crypto");

const app = express();
app.use(express.json());

// Environment variables
const PORT = process.env.PORT || 3002;
const ENV = process.env.ENV || "dev";
const VERSION = process.env.VERSION || "local";
const SERVICE = "instaclone-user";
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

// S3 configuration
const S3_BUCKET = process.env.S3_BUCKET || "instaclone-media";
const S3_REGION = process.env.S3_REGION || "us-east-1";
const s3Client = new S3Client({ region: S3_REGION });

// Multer configuration (memory storage for S3 upload)
const upload = multer({
  storage: multer.memoryStorage(),
  limits: {
    fileSize: 5 * 1024 * 1024 // 5MB limit
  },
  fileFilter: (req, file, cb) => {
    const allowedMimes = ["image/jpeg", "image/png", "image/gif", "image/webp"];
    if (allowedMimes.includes(file.mimetype)) {
      cb(null, true);
    } else {
      cb(new Error("Invalid file type. Only JPEG, PNG, GIF, and WebP are allowed"));
    }
  }
});

// Database connection pool
let pool;

// Initialize database
async function initDatabase() {
  try {
    pool = mysql.createPool(DB_CONFIG);
    const connection = await pool.getConnection();
    console.log(`✅ Database connected: ${DB_CONFIG.host}:${DB_CONFIG.port}/${DB_CONFIG.database}`);
    connection.release();
  } catch (error) {
    console.error("❌ Database connection failed:", error.message);
    process.exit(1);
  }
}

// Auth middleware
function authMiddleware(req, res, next) {
  try {
    const authHeader = req.headers.authorization;

    if (!authHeader || !authHeader.startsWith("Bearer ")) {
      return res.status(401).json({ error: "No token provided" });
    }

    const token = authHeader.replace("Bearer ", "");
    const decoded = jwt.verify(token, JWT_SECRET);

    req.user = decoded; // { userId, username, email }
    next();
  } catch (error) {
    if (error.name === "TokenExpiredError") {
      return res.status(401).json({ error: "Token expired" });
    }
    return res.status(401).json({ error: "Invalid token" });
  }
}

// Upload to S3
async function uploadToS3(file, key) {
  try {
    const command = new PutObjectCommand({
      Bucket: S3_BUCKET,
      Key: key,
      Body: file.buffer,
      ContentType: file.mimetype,
      ACL: "public-read"
    });

    await s3Client.send(command);

    return `https://${S3_BUCKET}.s3.${S3_REGION}.amazonaws.com/${key}`;
  } catch (error) {
    console.error("S3 upload error:", error);
    throw error;
  }
}

// Delete from S3
async function deleteFromS3(url) {
  try {
    const key = url.split(".amazonaws.com/")[1];
    if (!key) return;

    const command = new DeleteObjectCommand({
      Bucket: S3_BUCKET,
      Key: key
    });

    await s3Client.send(command);
  } catch (error) {
    console.error("S3 delete error:", error);
  }
}

// Health endpoint
app.get("/health", async (req, res) => {
  try {
    if (pool) {
      await pool.query("SELECT 1");
    }
    res.status(200).send("ok");
  } catch (error) {
    console.error("Health check failed:", error);
    res.status(503).send("unhealthy");
  }
});

// Version endpoint
app.get("/version", (req, res) => {
  res.status(200).json({
    service: SERVICE,
    version: VERSION,
    env: ENV,
    buildTime: BUILD_TIME
  });
});

// Get user profile
app.get("/users/:userId", async (req, res) => {
  try {
    const { userId } = req.params;

    const [rows] = await pool.query(
      `SELECT
        u.id,
        u.username,
        u.email,
        u.bio,
        u.profile_photo_url,
        u.created_at,
        (SELECT COUNT(*) FROM follows WHERE following_id = u.id) as followers_count,
        (SELECT COUNT(*) FROM follows WHERE follower_id = u.id) as following_count,
        (SELECT COUNT(*) FROM posts WHERE user_id = u.id) as posts_count
      FROM users u
      WHERE u.id = ?`,
      [userId]
    );

    if (rows.length === 0) {
      return res.status(404).json({ error: "User not found" });
    }

    res.status(200).json(rows[0]);
  } catch (error) {
    console.error("Get user error:", error);
    res.status(500).json({ error: "Internal server error" });
  }
});

// Update user profile
app.put("/users/:userId/profile", authMiddleware, async (req, res) => {
  try {
    const { userId } = req.params;
    const { bio, username } = req.body;

    // Check authorization
    if (parseInt(userId) !== req.user.userId) {
      return res.status(403).json({ error: "Unauthorized to update this profile" });
    }

    // Build update query dynamically
    const updates = [];
    const values = [];

    if (bio !== undefined) {
      updates.push("bio = ?");
      values.push(bio);
    }

    if (username !== undefined) {
      // Validate username
      if (!/^[a-zA-Z0-9_]{3,50}$/.test(username)) {
        return res.status(400).json({ error: "Invalid username format" });
      }
      updates.push("username = ?");
      values.push(username);
    }

    if (updates.length === 0) {
      return res.status(400).json({ error: "No fields to update" });
    }

    values.push(userId);

    const [result] = await pool.query(
      `UPDATE users SET ${updates.join(", ")} WHERE id = ?`,
      values
    );

    if (result.affectedRows === 0) {
      return res.status(404).json({ error: "User not found" });
    }

    // Get updated user
    const [rows] = await pool.query(
      "SELECT id, username, email, bio, profile_photo_url FROM users WHERE id = ?",
      [userId]
    );

    console.log(`✅ Profile updated for user: ${rows[0].username} (ID: ${userId})`);

    res.status(200).json({
      message: "Profile updated successfully",
      user: rows[0]
    });
  } catch (error) {
    console.error("Update profile error:", error);

    if (error.code === "ER_DUP_ENTRY") {
      return res.status(409).json({ error: "Username already exists" });
    }

    res.status(500).json({ error: "Internal server error" });
  }
});

// Upload avatar
app.post("/users/:userId/avatar", authMiddleware, upload.single("avatar"), async (req, res) => {
  try {
    const { userId } = req.params;

    // Check authorization
    if (parseInt(userId) !== req.user.userId) {
      return res.status(403).json({ error: "Unauthorized to update this profile" });
    }

    if (!req.file) {
      return res.status(400).json({ error: "No file uploaded" });
    }

    // Get current avatar URL to delete old one
    const [rows] = await pool.query(
      "SELECT profile_photo_url FROM users WHERE id = ?",
      [userId]
    );

    const oldAvatarUrl = rows[0]?.profile_photo_url;

    // Generate S3 key
    const fileExtension = req.file.originalname.split(".").pop();
    const fileName = `${crypto.randomBytes(16).toString("hex")}.${fileExtension}`;
    const s3Key = `profiles/user-${userId}/${fileName}`;

    // Upload to S3
    const avatarUrl = await uploadToS3(req.file, s3Key);

    // Update database
    await pool.query(
      "UPDATE users SET profile_photo_url = ? WHERE id = ?",
      [avatarUrl, userId]
    );

    // Delete old avatar from S3 (if exists)
    if (oldAvatarUrl) {
      await deleteFromS3(oldAvatarUrl);
    }

    console.log(`✅ Avatar uploaded for user ID: ${userId}`);

    res.status(200).json({
      message: "Avatar uploaded successfully",
      profilePhotoUrl: avatarUrl
    });
  } catch (error) {
    console.error("Upload avatar error:", error);
    res.status(500).json({ error: "Failed to upload avatar" });
  }
});

// Follow user
app.post("/users/:userId/follow", authMiddleware, async (req, res) => {
  try {
    const followingId = parseInt(req.params.userId);
    const followerId = req.user.userId;

    // Can't follow yourself
    if (followerId === followingId) {
      return res.status(400).json({ error: "Cannot follow yourself" });
    }

    // Check if user exists
    const [userRows] = await pool.query(
      "SELECT id FROM users WHERE id = ?",
      [followingId]
    );

    if (userRows.length === 0) {
      return res.status(404).json({ error: "User not found" });
    }

    // Insert follow relationship
    await pool.query(
      "INSERT INTO follows (follower_id, following_id) VALUES (?, ?)",
      [followerId, followingId]
    );

    console.log(`✅ User ${followerId} followed user ${followingId}`);

    res.status(200).json({ message: "User followed successfully" });
  } catch (error) {
    if (error.code === "ER_DUP_ENTRY") {
      return res.status(409).json({ error: "Already following this user" });
    }
    console.error("Follow error:", error);
    res.status(500).json({ error: "Internal server error" });
  }
});

// Unfollow user
app.delete("/users/:userId/unfollow", authMiddleware, async (req, res) => {
  try {
    const followingId = parseInt(req.params.userId);
    const followerId = req.user.userId;

    const [result] = await pool.query(
      "DELETE FROM follows WHERE follower_id = ? AND following_id = ?",
      [followerId, followingId]
    );

    if (result.affectedRows === 0) {
      return res.status(404).json({ error: "Follow relationship not found" });
    }

    console.log(`✅ User ${followerId} unfollowed user ${followingId}`);

    res.status(200).json({ message: "User unfollowed successfully" });
  } catch (error) {
    console.error("Unfollow error:", error);
    res.status(500).json({ error: "Internal server error" });
  }
});

// Get followers
app.get("/users/:userId/followers", async (req, res) => {
  try {
    const { userId } = req.params;
    const page = parseInt(req.query.page) || 1;
    const limit = Math.min(parseInt(req.query.limit) || 20, 100);
    const offset = (page - 1) * limit;

    const [rows] = await pool.query(
      `SELECT u.id, u.username, u.profile_photo_url
       FROM follows f
       JOIN users u ON f.follower_id = u.id
       WHERE f.following_id = ?
       ORDER BY f.created_at DESC
       LIMIT ? OFFSET ?`,
      [userId, limit, offset]
    );

    const [[{ total }]] = await pool.query(
      "SELECT COUNT(*) as total FROM follows WHERE following_id = ?",
      [userId]
    );

    res.status(200).json({
      followers: rows,
      totalCount: total,
      page,
      limit,
      hasMore: offset + rows.length < total
    });
  } catch (error) {
    console.error("Get followers error:", error);
    res.status(500).json({ error: "Internal server error" });
  }
});

// Get following
app.get("/users/:userId/following", async (req, res) => {
  try {
    const { userId } = req.params;
    const page = parseInt(req.query.page) || 1;
    const limit = Math.min(parseInt(req.query.limit) || 20, 100);
    const offset = (page - 1) * limit;

    const [rows] = await pool.query(
      `SELECT u.id, u.username, u.profile_photo_url
       FROM follows f
       JOIN users u ON f.following_id = u.id
       WHERE f.follower_id = ?
       ORDER BY f.created_at DESC
       LIMIT ? OFFSET ?`,
      [userId, limit, offset]
    );

    const [[{ total }]] = await pool.query(
      "SELECT COUNT(*) as total FROM follows WHERE follower_id = ?",
      [userId]
    );

    res.status(200).json({
      following: rows,
      totalCount: total,
      page,
      limit,
      hasMore: offset + rows.length < total
    });
  } catch (error) {
    console.error("Get following error:", error);
    res.status(500).json({ error: "Internal server error" });
  }
});

// Search users
app.get("/users/search", async (req, res) => {
  try {
    const { q } = req.query;
    const page = parseInt(req.query.page) || 1;
    const limit = Math.min(parseInt(req.query.limit) || 20, 100);
    const offset = (page - 1) * limit;

    if (!q || q.trim().length === 0) {
      return res.status(400).json({ error: "Search query is required" });
    }

    const searchTerm = `%${q}%`;

    const [rows] = await pool.query(
      `SELECT id, username, profile_photo_url, bio
       FROM users
       WHERE username LIKE ? OR email LIKE ?
       ORDER BY username
       LIMIT ? OFFSET ?`,
      [searchTerm, searchTerm, limit, offset]
    );

    const [[{ total }]] = await pool.query(
      "SELECT COUNT(*) as total FROM users WHERE username LIKE ? OR email LIKE ?",
      [searchTerm, searchTerm]
    );

    res.status(200).json({
      users: rows,
      totalCount: total,
      page,
      limit,
      hasMore: offset + rows.length < total
    });
  } catch (error) {
    console.error("Search users error:", error);
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
      console.log(`   S3 Bucket: ${S3_BUCKET}`);
    });
  } catch (error) {
    console.error("Failed to start server:", error);
    process.exit(1);
  }
}

// Graceful shutdown
process.on("SIGTERM", async () => {
  console.log("SIGTERM received, closing server...");
  if (pool) await pool.end();
  process.exit(0);
});

process.on("SIGINT", async () => {
  console.log("SIGINT received, closing server...");
  if (pool) await pool.end();
  process.exit(0);
});

startServer();
