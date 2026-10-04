import "server-only";
import { Socket } from "node:net";
import { basename } from "node:path";
import nodemailer from "nodemailer";
import { z } from "zod";
import { type Account, DomainError, findAccount, permissions, requireAdministrator } from "./accounts";
import { itemFor } from "./catalog";
import { database, transaction } from "./data";
import { openMediaFile } from "./playback";
import { remoteAddress } from "./remote";
import { seal, unseal } from "./secrets";
export const smtpInput = z.object({
  host: z
    .string()
    .max(253)
    .regex(/^[A-Za-z0-9.:-]*$/),
  port: z.number().int().min(1).max(65535),
  secure: z.boolean(),
  fromAddress: z.email(),
  username: z.string().max(256).default(""),
  password: z.string().max(4096).nullable().optional(),
});
const storedSchema = smtpInput.extend({ password: z.string() });
const defaults = {
  host: "",
  port: 587,
  secure: false,
  fromAddress: "leafwake@example.invalid",
  username: "",
  password: "",
};
function settings() {
  const row = database().prepare("SELECT content FROM product_settings WHERE key='smtp'").get();
  return row ? storedSchema.parse(unseal(z.string().parse(row.content))) : defaults;
}
export function smtpSettings(actor: Account) {
  requireAdministrator(actor);
  const { password, ...value } = settings();
  return { ...value, hasPassword: Boolean(password) };
}
export function saveSmtpSettings(actor: Account, input: z.infer<typeof smtpInput>) {
  requireAdministrator(actor);
  const previous = settings(),
    value = { ...input, password: input.password === null ? "" : (input.password ?? previous.password) };
  database()
    .prepare(
      "INSERT INTO product_settings VALUES('smtp',?) ON CONFLICT(key) DO UPDATE SET content=excluded.content",
    )
    .run(seal(value));
  return smtpSettings(actor);
}
const deviceSchema = z.object({
  name: z.string().trim().min(1).max(256),
  email: z.email(),
  availabilityOption: z.enum(["adminOrUp", "userOrUp", "guestOrUp", "specificUsers"]),
  users: z.array(z.string().max(256)).max(1000).default([]),
});
export const devicesInput = z.object({ ereaderDevices: z.array(deviceSchema).max(128) });
function devices() {
  const row = database().prepare("SELECT content FROM product_settings WHERE key='ereaders'").get();
  return row ? devicesInput.parse(unseal(z.string().parse(row.content))).ereaderDevices : [];
}
function available(actor: Account, device: z.infer<typeof deviceSchema>) {
  return (
    Boolean(actor.active) &&
    (device.availabilityOption === "guestOrUp" ||
      (["adminOrUp", "userOrUp"].includes(device.availabilityOption) &&
        ["root", "admin"].includes(actor.type)) ||
      (device.availabilityOption === "userOrUp" && actor.type === "user") ||
      (device.availabilityOption === "specificUsers" && device.users.includes(actor.id)))
  );
}
export function devicesFor(actor: Account) {
  return devices()
    .filter((d) => available(actor, d))
    .map((d) => ({ name: d.name }));
}
export function managedDevices(actor: Account) {
  requireAdministrator(actor);
  return { ereaderDevices: devices() };
}
export function saveDevices(actor: Account, input: z.infer<typeof devicesInput>) {
  requireAdministrator(actor);
  if (new Set(input.ereaderDevices.map((d) => d.name)).size !== input.ereaderDevices.length)
    throw new DomainError(400, "Device names must be unique");
  transaction((db) => {
    requireAdministrator(actor);
    for (const device of input.ereaderDevices) for (const id of device.users) findAccount(id);
    db.prepare(
      "INSERT INTO product_settings VALUES('ereaders',?) ON CONFLICT(key) DO UPDATE SET content=excluded.content",
    ).run(seal(input));
  });
  return managedDevices(actor);
}
export function savePersonalDevices(actor: Account, input: z.infer<typeof devicesInput>) {
  transaction((db) => {
    const current = findAccount(actor.id);
    if (!current.active || !permissions.parse(JSON.parse(current.permissions)).createEreader)
      throw new DomainError(403, "E-reader creation is not allowed");
    for (const device of input.ereaderDevices)
      if (
        device.availabilityOption !== "specificUsers" ||
        device.users.length !== 1 ||
        device.users[0] !== current.id
      )
        throw new DomainError(400, "Personal e-readers must be available only to your account");
    const others = devices().filter(
      (device) =>
        device.availabilityOption !== "specificUsers" ||
        device.users.length !== 1 ||
        device.users[0] !== current.id,
    );
    const combined = devicesInput.parse({ ereaderDevices: [...others, ...input.ereaderDevices] });
    if (new Set(combined.ereaderDevices.map((device) => device.name)).size !== combined.ereaderDevices.length)
      throw new DomainError(400, "Device names must be unique");
    db.prepare(
      "INSERT INTO product_settings VALUES('ereaders',?) ON CONFLICT(key) DO UPDATE SET content=excluded.content",
    ).run(seal(combined));
  });
  return { ereaderDevices: devicesFor(findAccount(actor.id)) };
}
export const sendEbookInput = z.object({
  libraryItemId: z.string().max(256),
  deviceName: z.string().max(256),
});
let active = 0;
export async function sendEbook(authorize: () => Account, input: z.infer<typeof sendEbookInput>) {
  if (active >= 2) throw new DomainError(503, "E-reader delivery is busy. Try again shortly");
  active++;
  let socket: Socket | undefined,
    deadline: ReturnType<typeof setTimeout> | undefined,
    policyTimer: ReturnType<typeof setInterval> | undefined;
  let opened: Awaited<ReturnType<typeof openMediaFile>> | undefined,
    transport: ReturnType<typeof nodemailer.createTransport> | undefined;
  try {
    const actor = authorize(),
      item = itemFor(actor, input.libraryItemId),
      file = item.media.ebookFile;
    const device = devices().find((d) => d.name === input.deviceName && available(actor, d));
    if (!device) throw new DomainError(403, "This e-reader is not available to your account");
    if (!file) throw new DomainError(400, "This item has no primary ebook");
    if (!permissions.parse(JSON.parse(actor.permissions)).download)
      throw new DomainError(403, "Downloads are not allowed");
    const config = settings();
    if (!config.host) throw new DomainError(400, "Configure SMTP before sending ebooks");
    const development = (process.env.LEAFWAKE_SMTP_ALLOWED_HOSTS ?? "").split(",").includes(config.host);
    const destination = await remoteAddress(
      config.host,
      AbortSignal.timeout(10000),
      process.env.LEAFWAKE_SMTP_ALLOWED_HOSTS ?? "",
    );
    opened = await openMediaFile(authorize, item.id, file.ino, true);
    if (opened.stat.size > 20 * 1024 * 1024)
      throw new DomainError(413, "Ebooks sent by email must be under 20 MiB");
    const buffer = Buffer.alloc(20 * 1024 * 1024 + 1);
    let position = 0;
    while (position < buffer.length) {
      const result = await opened.handle.read(buffer, position, buffer.length - position, position);
      if (!result.bytesRead) break;
      position += result.bytesRead;
    }
    if (position > 20 * 1024 * 1024) throw new DomainError(413, "Ebook exceeds the attachment size limit");
    const content = buffer.subarray(0, position);
    const current = authorize();
    itemFor(current, item.id);
    if (!devices().some((d) => d.name === device.name && d.email === device.email && available(current, d)))
      throw new DomainError(403, "E-reader access changed");
    if (!permissions.parse(JSON.parse(current.permissions)).download)
      throw new DomainError(403, "Downloads are not allowed");
    if (JSON.stringify(settings()) !== JSON.stringify(config))
      throw new DomainError(409, "SMTP settings changed; retry delivery");
    socket = new Socket();
    deadline = setTimeout(() => socket?.destroy(new Error("Delivery time limit exceeded")), 60000);
    policyTimer = setInterval(() => {
      try {
        const account = authorize();
        itemFor(account, item.id);
        if (
          !permissions.parse(JSON.parse(account.permissions)).download ||
          !devices().some((d) => d.name === device.name && d.email === device.email && available(account, d))
        )
          socket?.destroy(new Error("Delivery authority changed"));
      } catch {
        socket?.destroy(new Error("Delivery authority changed"));
      }
    }, 250);
    transport = nodemailer.createTransport({
      socket,
      host: destination.address,
      port: config.port,
      secure: config.secure,
      requireTLS: !development,
      tls: { servername: config.host, rejectUnauthorized: true },
      ...(config.username ? { auth: { user: config.username, pass: config.password } } : {}),
      connectionTimeout: 10000,
      greetingTimeout: 10000,
      socketTimeout: 20000,
      disableFileAccess: true,
      disableUrlAccess: true,
      logger: false,
      debug: false,
    });
    await transport.sendMail({
      from: config.fromAddress,
      to: device.email,
      subject: item.media.metadata.title.slice(0, 256),
      text: "Your requested ebook is attached.",
      attachments: [
        {
          filename: basename(file.metadata.filename.replaceAll("\\", "/")),
          content,
          contentType: opened.content.mimeType,
        },
      ],
    });
    return { success: true };
  } catch (error) {
    if (error instanceof DomainError) throw error;
    throw new DomainError(400, "E-reader delivery failed. Check the recipient and SMTP configuration.");
  } finally {
    if (deadline) clearTimeout(deadline);
    if (policyTimer) clearInterval(policyTimer);
    socket?.destroy();
    transport?.close();
    try {
      await opened?.handle.close();
    } finally {
      active--;
    }
  }
}
