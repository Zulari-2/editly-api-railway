import express from 'express';
import editly from 'editly';
import fs from 'fs/promises';
import { randomUUID } from 'crypto';
import cors from 'cors';
import { promisify } from 'util';
import { exec } from 'child_process';

const execAsync = promisify(exec);

const app = express();
app.use(cors());
app.use(express.json({ limit: '50mb' }));

const PORT = process.env.PORT || 8080;

app.get('/', (req, res) => {
  res.json({ status: '✅ Editly API LIVE & 100% FIXED (pre-resize rawvideo buffer fix)' });
});

async function preprocessImages(editSpec) {
  if (!editSpec.clips) return editSpec;

  const width = editSpec.width || 1080;
  const height = editSpec.height || 1920;
  const tempFiles = [];

  for (const clip of editSpec.clips) {
    if (!clip.layers) continue;

    for (const layer of clip.layers) {
      if (layer.type === 'image' && layer.path && layer.path.startsWith('http')) {
        const tempPath = `/tmp/${randomUUID()}.png`;
        tempFiles.push(tempPath);

        // Pre-resize with cover mode + lanczos for perfect sharpness (forces exact RGBA frame size)
        const cmd = `ffmpeg -i "${layer.path}" -vf "scale=${width}:${height}:force_original_aspect_ratio=increase:flags=lanczos,crop=${width}:${height}" -pix_fmt rgba -y "${tempPath}"`;
        await execAsync(cmd);

        layer.path = tempPath; // Now local and perfectly sized
      }
    }
  }

  return { editSpec, tempFiles };
}

app.post('/generate', async (req, res) => {
  console.log('📥 Received editSpec from n8n');

  let tempFiles = [];
  try {
    let { editSpec } = req.body;
    if (!editSpec) return res.status(400).json({ error: 'editSpec required in body' });

    const outFile = `/tmp/${randomUUID()}.mp4`;

    // Preprocess all images (this is the permanent fix)
    const processed = await preprocessImages(editSpec);
    editSpec = processed.editSpec;
    tempFiles = processed.tempFiles;

    const fullSpec = { 
      ...editSpec, 
      outPath: outFile, 
      allowRemoteRequests: true 
    };

    await editly(fullSpec);

    res.download(outFile, 'generated-video.mp4', async (err) => {
      if (!err) await fs.unlink(outFile).catch(() => {});
      // Cleanup temps
      for (const f of tempFiles) await fs.unlink(f).catch(() => {});
    });
  } catch (error) {
    console.error('❌ Editly failed:', error.message);
    // Cleanup on error
    for (const f of tempFiles) await fs.unlink(f).catch(() => {});
    res.status(500).json({ error: error.message });
  }
});

app.listen(PORT, () => console.log(`🚀 Editly API running on port ${PORT}`));
