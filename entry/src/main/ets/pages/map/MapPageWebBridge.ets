import { CertPolicy } from '../../network/CertPolicy';
import { fnWebLocalStorageSecretInjectScript } from '../../network/FnWebCookies';

/** 飞牛 H5 在业务码 401 时会整页跳到 /login；该页再登一次会覆盖会话并循环 */
export function isFnOsLoginUrl(url: string): boolean {
  const raw = url.trim();
  if (raw.length === 0) {
    return false;
  }
  const noHash = raw.split('#')[0];
  const scheme = noHash.indexOf('://');
  const pathStart = scheme >= 0 ? noHash.indexOf('/', scheme + 3) : 0;
  const pathAndQuery = pathStart >= 0 ? noHash.substring(pathStart) : noHash;
  const path = pathAndQuery.split('?')[0].toLowerCase();
  return path === '/login';
}

export function escapeRegexLiteral(value: string): string {
  const specials = '.*+?^${}()|[]\\';
  let out = '';
  for (let i = 0; i < value.length; i++) {
    const ch = value.charAt(i);
    if (specials.indexOf(ch) >= 0) {
      out += '\\' + ch;
    } else {
      out += ch;
    }
  }
  return out;
}

export function mapOfficialWebHideChromeScript(): string {
  return `(function(){function hide(){try{document.documentElement.style.paddingTop='0';document.body.style.paddingTop='0';var sels=['header','.header','.app-header','.page-header','.top-header','.layout-header','.nav-header','[class*="Header"]','[class*="header"]','[class*="top-bar"]','[class*="topBar"]','[class*="app-bar"]','[class*="navbar"]','[class*="nav-bar"]'];sels.forEach(function(sel){document.querySelectorAll(sel).forEach(function(el){var st=window.getComputedStyle(el);if(st.position==='fixed'||st.position==='sticky'||el.tagName==='HEADER'){el.style.setProperty('display','none','important');}});});document.querySelectorAll('*').forEach(function(el){if(el.childElementCount>0)return;var t=(el.textContent||'').trim();if(t==='飞牛相册'&&el.offsetHeight>0&&el.offsetHeight<80){var p=el.parentElement;for(var i=0;i<4&&p;i++){if(p.offsetHeight>0&&p.offsetHeight<120){p.style.setProperty('display','none','important');break;}p=p.parentElement;}}});}catch(e){}}hide();try{new MutationObserver(hide).observe(document.documentElement,{childList:true,subtree:true});}catch(e){}setTimeout(hide,300);setTimeout(hide,1000);})();`;
}

export function mapOfficialWebBootstrapScript(webSecretB64: string): string {
  let script = '';
  if (webSecretB64.length > 0) {
    script += fnWebLocalStorageSecretInjectScript(webSecretB64);
  }
  script += mapOfficialWebHideChromeScript();
  return script;
}

export function mapOfficialWebScriptRules(webBaseUrl: string): string[] {
  if (webBaseUrl.length <= 0) {
    return [];
  }
  return [`${escapeRegexLiteral(webBaseUrl)}/p`];
}

export function mapHandleOfficialWebSslError(
  event: OnSslErrorEventReceiveEvent,
  webBaseUrl: string,
  baseUrl: string
): boolean {
  try {
    if (CertPolicy.isTrusted(webBaseUrl) || CertPolicy.isTrusted(baseUrl)) {
      event.handler.handleConfirm();
      return true;
    }
    event.handler.handleCancel();
  } catch (_e) {
  }
  return false;
}
