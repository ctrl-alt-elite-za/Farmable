import { useEffect, useMemo, useRef } from 'react'
import { animate } from 'animejs'

type Kernel = {
  id: string
  x: number
  y: number
  scatterX: number
  scatterY: number
  scatterRotate: number
}

const rowColumns = [
  [2, 3, 4],
  [1, 2, 3, 4, 5],
  [1, 2, 3, 4, 5],
  [0, 1, 2, 3, 4, 5, 6],
  [0, 1, 2, 3, 4, 5, 6],
  [0, 1, 2, 3, 4, 5, 6],
  [0, 1, 2, 3, 4, 5, 6],
  [0, 1, 2, 3, 4, 5, 6],
  [0, 1, 2, 3, 4, 5, 6],
  [1, 2, 3, 4, 5],
  [2, 3, 4],
]

function seededValue(seed: number) {
  const value = Math.sin(seed * 91.73) * 10000
  return value - Math.floor(value)
}

function buildKernels(): Kernel[] {
  return rowColumns.flatMap((columns, row) =>
    columns.map((column) => {
      const seed = row * 11 + column + 1
      const direction = column === 3 ? (row % 2 === 0 ? -1 : 1) : Math.sign(column - 3)
      const xNoise = (seededValue(seed) - 0.5) * 48
      const yNoise = (seededValue(seed + 17) - 0.5) * 58

      return {
        id: `${row}-${column}`,
        x: 82 + column * 23 + (row % 2 === 0 ? 0 : 3),
        y: 104 + row * 30,
        scatterX: direction * (66 + Math.abs(column - 3) * 26) + xNoise,
        scatterY: (row - 5) * 15 + yNoise,
        scatterRotate: (seededValue(seed + 29) - 0.5) * 150,
      }
    }),
  )
}

export function CornScrollScene() {
  const sceneRef = useRef<HTMLDivElement>(null)
  const kernels = useMemo(buildKernels, [])

  useEffect(() => {
    const scene = sceneRef.current
    if (!scene) return

    const motionQuery = window.matchMedia('(prefers-reduced-motion: reduce)')
    if (motionQuery.matches) return

    const kernelNodes = scene.querySelectorAll<SVGRectElement>('.corn-kernel')
    const huskNodes = scene.querySelectorAll<SVGPathElement>('.corn-husk')
    const silkNodes = scene.querySelectorAll<SVGPathElement>('.corn-silk')

    const kernelAnimation = animate(kernelNodes, {
      translateX: (target?: unknown) => Number((target as SVGRectElement).dataset.scatterX),
      translateY: (target?: unknown) => Number((target as SVGRectElement).dataset.scatterY),
      rotate: (target?: unknown) => Number((target as SVGRectElement).dataset.scatterRotate),
      scale: 0.72,
      opacity: 0.28,
      duration: 1000,
      ease: 'inOut(3)',
      autoplay: false,
    })

    const huskAnimation = animate(huskNodes, {
      translateX: (_target?: unknown, index = 0) => (index === 0 ? -150 : 150),
      translateY: 90,
      rotate: (_target?: unknown, index = 0) => (index === 0 ? -24 : 24),
      opacity: 0.22,
      duration: 1000,
      ease: 'inOut(3)',
      autoplay: false,
    })

    const silkAnimation = animate(silkNodes, {
      translateY: -90,
      rotate: (_target?: unknown, index = 0) => (index % 2 === 0 ? -18 : 18),
      opacity: 0.12,
      duration: 1000,
      ease: 'inOut(3)',
      autoplay: false,
    })

    let frame = 0

    const update = () => {
      frame = 0
      const scrollRange = Math.max(document.documentElement.scrollHeight - window.innerHeight, 1)
      const rawProgress = Math.min(Math.max((window.scrollY - window.innerHeight * 0.12) / scrollRange, 0), 1)
      const progress = rawProgress * rawProgress * (3 - 2 * rawProgress)

      kernelAnimation.seek(kernelAnimation.duration * progress, true)
      huskAnimation.seek(huskAnimation.duration * progress, true)
      silkAnimation.seek(silkAnimation.duration * progress, true)
      scene.style.setProperty('--corn-progress', progress.toFixed(3))
    }

    const requestUpdate = () => {
      if (!frame) frame = window.requestAnimationFrame(update)
    }

    update()
    window.addEventListener('scroll', requestUpdate, { passive: true })
    window.addEventListener('resize', requestUpdate)

    return () => {
      window.removeEventListener('scroll', requestUpdate)
      window.removeEventListener('resize', requestUpdate)
      if (frame) window.cancelAnimationFrame(frame)
      kernelAnimation.revert()
      huskAnimation.revert()
      silkAnimation.revert()
    }
  }, [])

  return (
    <div className="corn-scene" ref={sceneRef} aria-hidden="true">
      <div className="corn-halo" />
      <svg className="corn-cob" viewBox="0 0 320 540" role="presentation">
        <defs>
          <linearGradient id="cob-body" x1="0" y1="0" x2="1" y2="1">
            <stop offset="0" stopColor="#f8d45b" />
            <stop offset="1" stopColor="#d89016" />
          </linearGradient>
          <linearGradient id="husk-left" x1="0" y1="0" x2="1" y2="1">
            <stop offset="0" stopColor="#78a844" />
            <stop offset="1" stopColor="#245c36" />
          </linearGradient>
          <linearGradient id="husk-right" x1="1" y1="0" x2="0" y2="1">
            <stop offset="0" stopColor="#8cb94d" />
            <stop offset="1" stopColor="#1d4b30" />
          </linearGradient>
          <filter id="corn-shadow" x="-40%" y="-30%" width="180%" height="180%">
            <feDropShadow dx="0" dy="18" stdDeviation="18" floodColor="#102e20" floodOpacity="0.28" />
          </filter>
        </defs>

        <g filter="url(#corn-shadow)">
          <path
            className="corn-silk"
            d="M145 84 C128 49 137 26 119 8 M158 79 C153 42 173 25 168 2 M174 88 C191 50 189 29 207 14"
            fill="none"
            stroke="#9a611b"
            strokeLinecap="round"
            strokeWidth="5"
          />
          <path
            d="M160 71 C104 73 72 135 76 258 C80 381 112 431 160 440 C208 431 240 381 244 258 C248 135 216 73 160 71Z"
            fill="url(#cob-body)"
          />

          <g className="corn-kernels">
            {kernels.map((kernel, index) => (
              <rect
                className="corn-kernel"
                data-scatter-x={kernel.scatterX}
                data-scatter-y={kernel.scatterY}
                data-scatter-rotate={kernel.scatterRotate}
                fill={index % 4 === 0 ? '#ffdf62' : index % 3 === 0 ? '#efb92c' : '#f7cb3f'}
                height="26"
                key={kernel.id}
                rx="8"
                stroke="#c78713"
                strokeWidth="1.25"
                width="20"
                x={kernel.x}
                y={kernel.y}
              />
            ))}
          </g>

          <path
            className="corn-husk"
            d="M151 429 C117 420 83 389 65 337 C35 251 56 183 85 144 C77 233 98 311 151 429Z"
            fill="url(#husk-left)"
          />
          <path
            className="corn-husk"
            d="M169 429 C203 420 237 389 255 337 C285 251 264 183 235 144 C243 233 222 311 169 429Z"
            fill="url(#husk-right)"
          />
          <path d="M153 425 H167 L180 515 H140Z" fill="#315f31" />
          <path d="M160 439 C147 468 147 492 150 516" fill="none" stroke="#95bb50" strokeWidth="4" />
        </g>
      </svg>
    </div>
  )
}
