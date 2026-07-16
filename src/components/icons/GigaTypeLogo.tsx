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
    className={`flex items-center gap-2 ${className ?? ""}`}
    style={{ width, height }}
    role="img"
    aria-label="GigaType"
  >
    <GigaTypeMark width="28%" height="auto" />
    <span className="text-xl font-bold tracking-tight text-text">GigaType</span>
  </div>
);

export default GigaTypeLogo;
