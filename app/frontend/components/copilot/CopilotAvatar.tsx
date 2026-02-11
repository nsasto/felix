import React from 'react';

export type AvatarState = 'idle' | 'listening' | 'thinking' | 'speaking' | 'error';

interface CopilotAvatarProps {
  state: AvatarState;
  size?: number;
}

/**
 * Animated avatar component for the Felix Copilot chat assistant.
 * Displays an SVG-based avatar with 5 animation states:
 * - idle: Gentle breathing, occasional blink
 * - listening: Attentive expression, subtle nod when user typing
 * - thinking: Processing indicator, gears turning animation
 * - speaking: Animated as tokens stream in (mouth moving)
 * - error: Worried expression, brief shake animation
 */
const CopilotAvatar: React.FC<CopilotAvatarProps> = ({ state, size = 48 }) => {
  // Get animation class based on state
  const getAnimationClass = () => {
    switch (state) {
      case 'idle':
        return 'copilot-avatar-idle';
      case 'listening':
        return 'copilot-avatar-listening';
      case 'thinking':
        return 'copilot-avatar-thinking';
      case 'speaking':
        return 'copilot-avatar-speaking';
      case 'error':
        return 'copilot-avatar-error';
      default:
        return 'copilot-avatar-idle';
    }
  };

  // Get face expression based on state
  const getFaceExpression = () => {
    switch (state) {
      case 'idle':
        return { eyeScale: 1, mouthWidth: 8, mouthCurve: 'M18,26 Q24,30 30,26' };
      case 'listening':
        return { eyeScale: 1.1, mouthWidth: 6, mouthCurve: 'M19,27 Q24,29 29,27' };
      case 'thinking':
        return { eyeScale: 0.8, mouthWidth: 4, mouthCurve: 'M20,27 Q24,27 28,27' };
      case 'speaking':
        return { eyeScale: 1, mouthWidth: 10, mouthCurve: 'M17,26 Q24,32 31,26' };
      case 'error':
        return { eyeScale: 1.2, mouthWidth: 8, mouthCurve: 'M18,30 Q24,26 30,30' };
      default:
        return { eyeScale: 1, mouthWidth: 8, mouthCurve: 'M18,26 Q24,30 30,26' };
    }
  };

  const expression = getFaceExpression();

  return (
    <div
      className={`copilot-avatar ${getAnimationClass()}`}
      style={{ width: size, height: size }}
    >
      <svg
        viewBox="0 0 48 48"
        fill="none"
        xmlns="http://www.w3.org/2000/svg"
        className="w-full h-full"
      >
        {/* Background circle with gradient */}
        <defs>
          <linearGradient id="avatarGradient" x1="0%" y1="0%" x2="100%" y2="100%">
            <stop offset="0%" stopColor="#738ef1" />
            <stop offset="100%" stopColor="#5268e8" />
          </linearGradient>
          <linearGradient id="glowGradient" x1="0%" y1="0%" x2="100%" y2="100%">
            <stop offset="0%" stopColor="#9db4f7" stopOpacity="0.4" />
            <stop offset="100%" stopColor="#738ef1" stopOpacity="0" />
          </linearGradient>
          {/* Thinking spinner gradient */}
          <linearGradient id="spinnerGradient" x1="0%" y1="0%" x2="100%" y2="0%">
            <stop offset="0%" stopColor="#738ef1" stopOpacity="0" />
            <stop offset="50%" stopColor="#738ef1" stopOpacity="1" />
            <stop offset="100%" stopColor="#9db4f7" stopOpacity="1" />
          </linearGradient>
        </defs>

        {/* Outer glow (subtle) */}
        <circle cx="24" cy="24" r="23" fill="url(#glowGradient)" className="opacity-50" />

        {/* Main avatar circle */}
        <circle cx="24" cy="24" r="20" fill="url(#avatarGradient)" />

        {/* Inner highlight */}
        <circle cx="24" cy="24" r="18" fill="none" stroke="white" strokeOpacity="0.1" strokeWidth="1" />

        {/* Left eye */}
        <g className="copilot-avatar-eye-left">
          <ellipse
            cx="17"
            cy="20"
            rx={2.5 * expression.eyeScale}
            ry={3 * expression.eyeScale}
            fill="white"
          />
          <circle cx="17.5" cy="20" r={1.2 * expression.eyeScale} fill="#1e293b" />
        </g>

        {/* Right eye */}
        <g className="copilot-avatar-eye-right">
          <ellipse
            cx="31"
            cy="20"
            rx={2.5 * expression.eyeScale}
            ry={3 * expression.eyeScale}
            fill="white"
          />
          <circle cx="31.5" cy="20" r={1.2 * expression.eyeScale} fill="#1e293b" />
        </g>

        {/* Mouth */}
        <path
          d={expression.mouthCurve}
          stroke="white"
          strokeWidth="2"
          strokeLinecap="round"
          fill="none"
          className="copilot-avatar-mouth"
        />

        {/* Thinking spinner (only visible in thinking state) */}
        {state === 'thinking' && (
          <circle
            cx="24"
            cy="24"
            r="22"
            fill="none"
            stroke="url(#spinnerGradient)"
            strokeWidth="2"
            strokeLinecap="round"
            strokeDasharray="20 100"
            className="copilot-avatar-spinner"
          />
        )}

        {/* Error indicator (only visible in error state) */}
        {state === 'error' && (
          <g className="copilot-avatar-error-indicator">
            {/* Sweat drop */}
            <path
              d="M10,14 Q10,18 12,18 Q14,18 14,14 Q12,10 10,14"
              fill="#9db4f7"
              fillOpacity="0.6"
            />
          </g>
        )}

        {/* Eyebrows - change based on state */}
        {state === 'listening' && (
          <>
            <path d="M14,15 Q17,13 20,15" stroke="white" strokeWidth="1.5" strokeLinecap="round" fill="none" />
            <path d="M28,15 Q31,13 34,15" stroke="white" strokeWidth="1.5" strokeLinecap="round" fill="none" />
          </>
        )}

        {state === 'thinking' && (
          <>
            <path d="M14,16 L20,16" stroke="white" strokeWidth="1.5" strokeLinecap="round" fill="none" />
            <path d="M28,16 L34,16" stroke="white" strokeWidth="1.5" strokeLinecap="round" fill="none" />
          </>
        )}

        {state === 'error' && (
          <>
            <path d="M14,17 Q17,14 20,17" stroke="white" strokeWidth="1.5" strokeLinecap="round" fill="none" />
            <path d="M28,17 Q31,14 34,17" stroke="white" strokeWidth="1.5" strokeLinecap="round" fill="none" />
          </>
        )}
      </svg>

      {/* CSS Animations */}
      <style>{`
        .copilot-avatar {
          position: relative;
          display: inline-flex;
          align-items: center;
          justify-content: center;
          transition: transform 0.3s ease;
        }

        /* Idle state: Gentle breathing animation */
        .copilot-avatar-idle {
          animation: copilot-breathe 3s ease-in-out infinite;
        }

        @keyframes copilot-breathe {
          0%, 100% { transform: scale(1); }
          50% { transform: scale(1.02); }
        }

        /* Listening state: Attentive nod */
        .copilot-avatar-listening {
          animation: copilot-nod 1.5s ease-in-out infinite;
        }

        @keyframes copilot-nod {
          0%, 100% { transform: translateY(0); }
          50% { transform: translateY(-2px); }
        }

        /* Thinking state: Slight pulse while spinner rotates */
        .copilot-avatar-thinking {
          animation: copilot-pulse 1.5s ease-in-out infinite;
        }

        @keyframes copilot-pulse {
          0%, 100% { transform: scale(1); opacity: 1; }
          50% { transform: scale(0.98); opacity: 0.9; }
        }

        .copilot-avatar-spinner {
          animation: copilot-spin 1.2s linear infinite;
          transform-origin: center;
        }

        @keyframes copilot-spin {
          0% { transform: rotate(0deg); }
          100% { transform: rotate(360deg); }
        }

        /* Speaking state: Animated mouth/bounce */
        .copilot-avatar-speaking {
          animation: copilot-speak-bounce 0.5s ease-in-out infinite;
        }

        @keyframes copilot-speak-bounce {
          0%, 100% { transform: translateY(0); }
          50% { transform: translateY(-1px); }
        }

        .copilot-avatar-speaking .copilot-avatar-mouth {
          animation: copilot-mouth-move 0.3s ease-in-out infinite;
        }

        @keyframes copilot-mouth-move {
          0%, 100% { transform: scaleY(1); }
          50% { transform: scaleY(1.2); }
        }

        /* Error state: Shake animation */
        .copilot-avatar-error {
          animation: copilot-shake 0.4s ease-in-out 3;
        }

        @keyframes copilot-shake {
          0%, 100% { transform: translateX(0); }
          25% { transform: translateX(-4px); }
          75% { transform: translateX(4px); }
        }

        /* Eye blink animation (for idle) */
        .copilot-avatar-idle .copilot-avatar-eye-left,
        .copilot-avatar-idle .copilot-avatar-eye-right {
          animation: copilot-blink 4s ease-in-out infinite;
        }

        @keyframes copilot-blink {
          0%, 45%, 55%, 100% { transform: scaleY(1); }
          50% { transform: scaleY(0.1); }
        }
      `}</style>
    </div>
  );
};

export default CopilotAvatar;
