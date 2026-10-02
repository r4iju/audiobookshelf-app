// foliate-js ships plain JavaScript; these are the parts of its MOBI/KF8 parser the reader uses.
declare module "foliate-js/mobi.js" {
  export interface MobiTocItem {
    label: string;
    href: string;
    subitems?: MobiTocItem[];
  }
  export interface MobiSection {
    /** Absent for KF8 parts that are not read in order. */
    load?: () => Promise<string>;
    size?: number;
  }
  export interface MobiBook {
    sections: MobiSection[];
    toc?: MobiTocItem[];
    resolveHref(
      href: string,
    ):
      | { index: number; anchor: (doc: Document) => Element | null }
      | undefined
      | Promise<{ index: number; anchor: (doc: Document) => Element | null } | undefined>;
    isExternal(uri: string): boolean;
    destroy(): void;
  }
  export function isMOBI(file: Blob): Promise<boolean>;
  export class MOBI {
    constructor(options: { unzlib: (data: Uint8Array) => Uint8Array });
    open(file: Blob): Promise<MobiBook>;
  }
}

declare module "foliate-js/vendor/fflate.js" {
  export function unzlibSync(data: Uint8Array): Uint8Array;
}
