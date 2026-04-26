const fs = require('fs');
const path = require('path');
const https = require('https');

const ROOT = process.cwd();
const TREE_PATH = path.join(ROOT, 'ui_design_kit_subtree.json');
const OUTPUT_DIR = path.join(ROOT, 'docs', 'huawei_ui_design_kit');
const API_URL = 'https://developer.huawei.com/consumer/cn/documentPortal/getDocumentById';
const SITE_PREFIX = 'https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/';

function ensureDir(dir) {
  fs.mkdirSync(dir, { recursive: true });
}

function readJson(file) {
  return JSON.parse(fs.readFileSync(file, 'utf8'));
}

function slugToUrl(slug) {
  return `${SITE_PREFIX}${slug}`;
}

function escapeHtml(text) {
  return String(text)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;');
}

function flattenNodes(nodes, depth = 0, acc = []) {
  for (const node of nodes || []) {
    acc.push({
      title: node.nodeName,
      slug: node.relateDocument,
      docId: node.relateDocId,
      depth,
      isLeaf: Boolean(node.isLeaf),
    });
    flattenNodes(node.children, depth + 1, acc);
  }
  return acc;
}

function sanitizeFilename(slug) {
  return slug.replace(/[^a-zA-Z0-9._-]/g, '_');
}

function postJson(url, body, referer) {
  return new Promise((resolve, reject) => {
    const raw = JSON.stringify(body);
    const req = https.request(
      url,
      {
        method: 'POST',
        headers: {
          'content-type': 'application/json',
          'content-length': Buffer.byteLength(raw),
          origin: 'https://developer.huawei.com',
          referer,
          'user-agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/135.0.0.0 Safari/537.36',
        },
      },
      (res) => {
        let data = '';
        res.setEncoding('utf8');
        res.on('data', (chunk) => {
          data += chunk;
        });
        res.on('end', () => {
          if (res.statusCode && res.statusCode >= 400) {
            reject(new Error(`HTTP ${res.statusCode}: ${data.slice(0, 300)}`));
            return;
          }
          try {
            resolve(JSON.parse(data));
          } catch (error) {
            reject(new Error(`Invalid JSON response: ${data.slice(0, 300)}`));
          }
        });
      }
    );
    req.on('error', reject);
    req.write(raw);
    req.end();
  });
}

async function fetchDocument(slug) {
  const response = await postJson(API_URL, { language: 'cn', objectId: slug }, slugToUrl(slug));
  if (response.code !== 0 || !response.value) {
    throw new Error(`Fetch failed for ${slug}: ${response.message || response.code}`);
  }
  return response.value;
}

function renderDocumentMarkdown(node, doc) {
  const html = doc.content && doc.content.content ? doc.content.content : '';
  const anchorLines = Array.isArray(doc.anchorList)
    ? doc.anchorList.map((anchor) => `- ${'  '.repeat(Math.max(0, Number(anchor.level || 1) - 1))}${anchor.title}`)
    : [];

  return [
    `# ${doc.title || node.title}`,
    '',
    `- 页面标题: ${doc.title || node.title}`,
    `- slug: \`${node.slug}\``,
    `- 原始地址: ${slugToUrl(node.slug)}`,
    `- 文档ID: \`${doc.docId || node.docId || ''}\``,
    `- 更新时间: ${doc.updatedDate || '未知'}`,
    '',
    '## 锚点目录',
    '',
    ...(anchorLines.length ? anchorLines : ['- 无']),
    '',
    '## 正文',
    '',
    '<!-- 华为接口返回为 HTML，这里原样保留，便于后续继续转换或抽取。 -->',
    '',
    html,
    '',
  ].join('\n');
}

function renderIndex(nodes) {
  const lines = [
    '# HarmonyOS UI Design Kit 本地索引',
    '',
    `- 拉取时间: ${new Date().toISOString()}`,
    `- 来源: ${slugToUrl('ui-design-kit-guide')}`,
    `- 输出目录: \`${path.relative(ROOT, OUTPUT_DIR)}\``,
    '',
    '## 页面列表',
    '',
  ];

  for (const node of nodes) {
    const indent = '  '.repeat(node.depth);
    lines.push(`- ${indent}[${node.title}](./${sanitizeFilename(node.slug)}.md)`);
  }

  lines.push('', '## 说明', '', '- 每个页面文件都保留了华为接口返回的 HTML 正文。', '- 如需进一步转纯 Markdown，可在此基础上继续做 HTML 到 Markdown 的转换。', '');
  return lines.join('\n');
}

async function main() {
  ensureDir(OUTPUT_DIR);

  const tree = readJson(TREE_PATH);
  const nodes = flattenNodes(tree.children || []);
  const rootNode = {
    title: 'UI Design Kit（UI设计套件）',
    slug: 'ui-design-kit-guide',
    docId: '9316deffc74b46df87a96344d1c4c24b',
    depth: 0,
    isLeaf: false,
  };
  const allNodes = [rootNode, ...nodes];
  const failures = [];

  for (const node of allNodes) {
    try {
      const doc = await fetchDocument(node.slug);
      const output = renderDocumentMarkdown(node, doc);
      const file = path.join(OUTPUT_DIR, `${sanitizeFilename(node.slug)}.md`);
      fs.writeFileSync(file, output, 'utf8');
      console.log(`OK ${node.slug}`);
    } catch (error) {
      failures.push({ slug: node.slug, message: error.message });
      console.error(`FAIL ${node.slug}: ${error.message}`);
    }
  }

  fs.writeFileSync(path.join(OUTPUT_DIR, 'README.md'), renderIndex(allNodes), 'utf8');
  fs.writeFileSync(path.join(OUTPUT_DIR, 'fetch_failures.json'), JSON.stringify(failures, null, 2), 'utf8');

  if (failures.length) {
    console.error(`Completed with ${failures.length} failure(s).`);
    process.exitCode = 1;
    return;
  }

  console.log(`Fetched ${allNodes.length} pages into ${OUTPUT_DIR}`);
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
