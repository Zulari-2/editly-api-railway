import express from 'express';
import editly from 'editly';
import fs from 'fs/promises';
import { randomUUID } from 'crypto';
import cors from 'cors';

const app = express();
app.use(cors());
app.use(express.json({ limit: '50mb' }));

const PORT = process.env.PORT || 8080;

app.get('/', (req, res) => {
  res.json({ status: '✅ Editly API LIVE & 100% STABLE (no zoom = no rawvideo error)' });
});

app.post('/generate', async (req, res) => {
  console.log('📥 Received editSpec from n8n');

  try {
    let { editSpec } = req.body;
    if (!editSpec) return res.status(400).json({ error: 'editSpec required in body' });

    const outFile = `/tmp/${randomUUID()}.mp4`;

    // AUTO-FIX: Make every image sharp + fill screen (no blurry ever)
    if (editSpec.clips) {
      editSpec.clips = editSpec.clips.map(clip => {
        if (clip.layers) {
          clip.layers = clip.layers.map(layer => {
            if (layer.type === 'image') {
              return {
                ...layer,
                width: editSpec.width || 1080,
                height: editSpec.height || 1920,
                resizeMode: 'cover'   // <-- this fixes blurry
              };
            }
            return layer;
          });
        }
        return clip;
      });
    }

    const fullSpec = { 
      ...editSpec, 
      outPath: outFile, 
      allowRemoteRequests: true 
    };

    await editly(fullSpec);

    res.download(outFile, 'generated-video.mp4', async (err) => {
      if (!err) await fs.unlink(outFile).catch(() => {});
    });
  } catch (error) {
    console.error('❌ Failed:', error.message);
    res.status(500).json({ error: error.message });
  }
});

app.listen(PORT, () => console.log(`🚀 Editly API running on port ${PORT}`));
