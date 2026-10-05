export function OriginNotice() {
  return (
    <div className="space-y-2 text-sm text-muted">
      <p>
        Audiobook Loft began as an independently maintained fork of the Audiobookshelf app. Its browser and
        backend have been rewritten. Upstream copyright and license notices are retained. It is not affiliated
        with or endorsed by the Audiobookshelf project.
      </p>
      <p>
        Open source under GPLv3, with applicable third-party licenses retained.{" "}
        <a className="underline" href="https://github.com/r4iju/audiobookshelf-app/releases">
          Source and license notices
        </a>
      </p>
    </div>
  );
}
