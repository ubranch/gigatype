/* eslint-disable i18next/no-literal-string */
import GigaTypeMark from "./GigaTypeMark";

interface GigaTypeLogoProps {
  width?: number;
  height?: number;
  className?: string;
}

const GigaTypeLogo = ({
  width = 200,
  height,
  className,
}: GigaTypeLogoProps) => (
  <div
    className={`flex max-w-full items-center justify-center gap-2 overflow-hidden ${className ?? ""}`}
    style={{ width, maxWidth: "100%", height }}
    role="img"
    aria-label="GigaType"
  >
    <GigaTypeMark
      width={24}
      height={24}
      className="shrink-0"
      aria-hidden="true"
    />
    <span className="min-w-0 truncate text-lg font-bold tracking-tight text-text">
      GigaType
    </span>
  </div>
);

export default GigaTypeLogo;
