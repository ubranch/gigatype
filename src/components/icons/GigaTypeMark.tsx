/* eslint-disable i18next/no-literal-string */
interface GigaTypeMarkProps {
  width?: number | string;
  height?: number | string;
  className?: string;
}

const GigaTypeMark = ({
  width = 126,
  height = 126,
  className,
}: GigaTypeMarkProps) => (
  <svg
    width={width}
    height={height}
    className={className}
    viewBox="0 0 128 128"
    role="img"
    aria-label="GigaType"
    xmlns="http://www.w3.org/2000/svg"
  >
    <rect
      x="8"
      y="8"
      width="112"
      height="112"
      rx="30"
      fill="var(--color-logo-primary)"
    />
    <path
      d="M84 43a32 32 0 1 0 4 42V66H65"
      fill="none"
      stroke="var(--color-logo-stroke)"
      strokeWidth="10"
      strokeLinecap="round"
      strokeLinejoin="round"
    />
    <path
      d="M43 57v14M53 51v26M63 57v14"
      fill="none"
      stroke="var(--color-logo-stroke)"
      strokeWidth="5"
      strokeLinecap="round"
    />
  </svg>
);

export default GigaTypeMark;
