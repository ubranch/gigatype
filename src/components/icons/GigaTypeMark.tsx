import type { SVGProps } from "react";

interface GigaTypeMarkProps
  extends Omit<SVGProps<SVGSVGElement>, "width" | "height"> {
  width?: number | string;
  height?: number | string;
}

const GigaTypeMark = ({
  width = 126,
  height = 126,
  className,
  role,
  "aria-label": ariaLabel,
  "aria-hidden": ariaHidden,
  ...svgProps
}: GigaTypeMarkProps) => {
  const isDecorative = ariaHidden === true || ariaHidden === "true";

  return (
    <svg
      {...svgProps}
      width={width}
      height={height}
      className={className}
      viewBox="0 0 128 128"
      role={isDecorative ? undefined : (role ?? "img")}
      aria-label={isDecorative ? undefined : (ariaLabel ?? "GigaType")}
      aria-hidden={ariaHidden}
      data-brand="magic-mic"
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
        d="M28 58v3c0 25 16 43 36 43s36-18 36-43v-3"
        fill="none"
        stroke="var(--color-logo-stroke)"
        strokeWidth="8"
        strokeLinecap="round"
      />
      <path
        d="M28 58v3c0 25 16 43 36 43s36-18 36-43v-3"
        fill="none"
        stroke="#B85BE8"
        strokeWidth="3"
        strokeLinecap="round"
      />
      <path
        d="M64 104v9M49 114h30"
        fill="none"
        stroke="var(--color-logo-stroke)"
        strokeWidth="7"
        strokeLinecap="round"
      />
      <rect
        data-part="mic-body"
        x="43"
        y="22"
        width="42"
        height="59"
        rx="21"
        fill="#FFF8FB"
        stroke="var(--color-logo-stroke)"
        strokeWidth="6"
      />
      <g data-part="face">
        <circle cx="56" cy="44" r="3" fill="var(--color-logo-stroke)" />
        <circle cx="72" cy="44" r="3" fill="var(--color-logo-stroke)" />
        <circle cx="54" cy="55" r="3.5" fill="#F59AC4" />
        <circle cx="74" cy="55" r="3.5" fill="#F59AC4" />
        <path
          d="M57 54c4 6 10 6 14 0"
          fill="none"
          stroke="var(--color-logo-stroke)"
          strokeWidth="3"
          strokeLinecap="round"
        />
      </g>
      <path
        d="m98 19 3 7 7 3-7 3-3 7-3-7-7-3 7-3 3-7Z"
        fill="#F59AC4"
        stroke="var(--color-logo-stroke)"
        strokeWidth="2"
        strokeLinejoin="round"
      />
    </svg>
  );
};

export default GigaTypeMark;
