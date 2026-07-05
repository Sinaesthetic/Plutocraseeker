import { cp, mkdir, rm } from "node:fs/promises";
import { createWriteStream } from "node:fs";
import { spawn } from "node:child_process";
import path from "node:path";
import process from "node:process";

const addonName = "Plutocraseeker";
const root = process.cwd();
const distDir = path.join(root, "dist");
const packageDir = path.join(distDir, addonName);
const zipPath = path.join(root, `${addonName}.zip`);

const addonFiles = [
  "Core.lua",
  "UI.lua",
  "AtlasBrowser.lua",
  "Plutocraseeker.toc",
  "Plutocraseeker_Mists.toc",
  "assets/plutocraseeker-icon.tga",
];

function run(command, args, options = {}) {
  return new Promise((resolve, reject) => {
    const child = spawn(command, args, {
      stdio: "inherit",
      ...options,
    });

    child.on("error", reject);
    child.on("exit", (code) => {
      if (code === 0) {
        resolve();
      } else {
        reject(new Error(`${command} exited with code ${code}`));
      }
    });
  });
}

async function copyAddonFiles() {
  await rm(distDir, { recursive: true, force: true });
  await rm(zipPath, { force: true });
  await mkdir(packageDir, { recursive: true });

  for (const file of addonFiles) {
    const source = path.join(root, file);
    const destination = path.join(packageDir, file);
    await mkdir(path.dirname(destination), { recursive: true });
    await cp(source, destination);
  }
}

async function zipOnWindows() {
  const command = [
    "$ErrorActionPreference = 'Stop'",
    `Compress-Archive -Path '${packageDir.replaceAll("'", "''")}' -DestinationPath '${zipPath.replaceAll("'", "''")}' -Force`,
  ].join("; ");

  await run("powershell", ["-NoProfile", "-Command", command]);
}

async function zipOnUnix() {
  await run("zip", ["-r", zipPath, addonName], { cwd: distDir });
}

async function main() {
  await copyAddonFiles();

  if (process.platform === "win32") {
    await zipOnWindows();
  } else {
    await zipOnUnix();
  }

  console.log(`Created ${path.relative(root, zipPath)}`);
}

main().catch((error) => {
  console.error(error.message);
  process.exitCode = 1;
});
