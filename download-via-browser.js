#!/usr/bin/env node

const { chromium } = require("playwright");

const targetUrl = process.argv[2];
const savePath = process.argv[3];

if (!targetUrl || !savePath) {
    process.exit(1);
}

(async () => {
    let browser = null;

    try {
        browser = await chromium.launch({
            headless: true,
            executablePath: "/usr/bin/chromium-headless-shell",
            args: [
                "--no-sandbox",
                "--disable-setuid-sandbox",
                "--disable-gpu",
                "--disable-dev-shm-usage",
                "--disable-blink-features=AutomationControlled",
            ],
        });

        const context = await browser.newContext({
            // 实测不需要
            // userAgent: 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
        });

        // 参考文档
        // https://playwright.dev/docs/downloads
        // https://playwright.dev/docs/api/class-download

        const page = await context.newPage();
        const downloadPromise = page.waitForEvent("download", {
            timeout: 60000,
        });

        await page.goto(targetUrl, { waitUntil: "commit" }).catch((e) => {
            // 下载直链会触发 'Download is starting' 异常，要手动忽略
            // https://github.com/microsoft/playwright/blob/v1.60.0/tests/library/download.spec.ts#L68
            if (!e.message.includes("Download is starting")) {
                throw e;
            }
        });
        console.error("Page opened:", targetUrl);

        const download = await downloadPromise;
        const suggestedFilename = download.suggestedFilename();
        console.error("Download started:", suggestedFilename, savePath);

        await download.saveAs(savePath);
        console.error("Download completed:", suggestedFilename, savePath);
    } catch (err) {
        console.error("Download failed:", err);
        process.exitCode = 1;
    } finally {
        if (browser) {
            await browser.close();
        }
    }
})();
