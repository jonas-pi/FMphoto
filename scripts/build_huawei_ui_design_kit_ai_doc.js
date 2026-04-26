const fs = require('fs');
const path = require('path');

const ROOT = process.cwd();
const TREE_PATH = path.join(ROOT, 'ui_design_kit_subtree.json');
const SOURCE_DIR = path.join(ROOT, 'docs', 'huawei_ui_design_kit');
const OUTPUT_PATH = path.join(SOURCE_DIR, 'HUAWEI_UI_DESIGN_KIT_AI_CONTEXT.md');

function readJson(file) {
  return JSON.parse(fs.readFileSync(file, 'utf8'));
}

function readText(file) {
  return fs.readFileSync(file, 'utf8');
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

function extractSection(md, heading) {
  const escaped = heading.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const regex = new RegExp(`## ${escaped}\\r?\\n([\\s\\S]*?)(\\r?\\n## |$)`);
  const match = md.match(regex);
  return match ? match[1].trim() : '';
}

function buildToc(nodes) {
  return nodes
    .map((node) => `- ${'  '.repeat(node.depth)}${node.title} | \`${node.slug}\``)
    .join('\n');
}

function buildQuickRules() {
  return [
    '- 优先保持 HarmonyOS 风格一致性，不随意替换为通用 Android、iOS 或 Web 视觉语言。',
    '- 涉及导航、侧边栏、底部页签、即时操作、核心操作栏、列表、视效、多窗、沉浸光感时，优先复用 UI Design Kit 对应能力。',
    '- 多设备适配是默认目标，输出方案时同时考虑 Phone、Tablet、PC/2in1、Wearable、TV 的差异与边界。',
    '- 页面与组件应强调高端、精致、沉浸、统一体验，避免廉价装饰、随意阴影和风格拼贴。',
    '- 如果已有 HDS 组件或光影能力可满足需求，优先建议采用官方能力，而不是自造近似控件。',
    '- 做视觉设计时，优先检查是否可用动态模糊、流光、按压阴影、沉浸光感材质等官方能力增强体验。',
    '- 图标与 Symbol 资源优先采用官方推荐流程，避免随意导入不符合规范的图标风格。',
    '- 生成页面、组件或设计说明时，要明确支持设备、交互方式、限制条件和兼容边界。',
    '- 如能力仅支持中国大陆或特定设备，应在方案中明确标注，不默认全区域、全设备可用。',
  ].join('\n');
}

function buildDocument() {
  const tree = readJson(TREE_PATH);
  const rootNode = {
    title: 'UI Design Kit（UI设计套件）',
    slug: 'ui-design-kit-guide',
    docId: '9316deffc74b46df87a96344d1c4c24b',
    depth: 0,
    isLeaf: false,
  };
  const nodes = [rootNode, ...flattenNodes(tree.children || [])];

  const introPath = path.join(SOURCE_DIR, 'ui-design-introduction.md');
  const intro = readText(introPath);
  const introMeta = extractSection(intro, '正文');

  const lines = [
    '# Huawei UI Design Kit AI Context',
    '',
    '## 用途',
    '',
    '这份文档用于给 AI 提供 HarmonyOS UI Design Kit 的本地约束上下文。',
    '它不是简单的网页列表，而是把抓取范围、使用原则、目录索引和正文来源统一收敛到一个文件里，方便在提示词、系统约束或项目规范中直接引用。',
    '',
    '## 抓取状态',
    '',
    '- 已成功拉取页面数: 45',
    '- 文档来源: `https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ui-design-kit-guide`',
    '- 本地原始页面目录: `docs/huawei_ui_design_kit/`',
    '- 每个页面均已保存为单独 Markdown 文件，正文保留官方接口返回 HTML。',
    '',
    '## 给 AI 的核心约束',
    '',
    buildQuickRules(),
    '',
    '## 顶层设计目标',
    '',
    '以下内容摘自 `UI Design Kit简介` 的本地正文，用于让 AI 理解这套设计体系的总体目标。',
    '',
    introMeta || '未提取到简介正文，请回看 `ui-design-introduction.md`。',
    '',
    '## 完整目录索引',
    '',
    buildToc(nodes),
    '',
    '## 使用方式建议',
    '',
    '- 如果你要让 AI 生成 HarmonyOS 页面或组件，可把本文件整体作为上下文输入。',
    '- 如果任务只涉及某一类能力，可再补充对应子页面原文，例如导航、页签、列表或视效页面。',
    '- 如果你想进一步提高稳定性，建议再额外写一份项目内的“允许/禁止事项”清单，与本文一起使用。',
    '',
    '## 本地页面映射',
    '',
    ...nodes.map((node) => `- ${node.title}: \`docs/huawei_ui_design_kit/${node.slug}.md\``),
    '',
    '## 附录',
    '',
    '- 本文件偏向 AI 约束与检索入口。',
    '- 需要完整原文时，请直接读取 `docs/huawei_ui_design_kit/` 中对应页面。',
    '- 需要重新抓取时，可运行 `node scripts/fetch_huawei_ui_design_kit.js`。',
    '',
  ];

  fs.writeFileSync(OUTPUT_PATH, lines.join('\n'), 'utf8');
  return OUTPUT_PATH;
}

const output = buildDocument();
console.log(output);
