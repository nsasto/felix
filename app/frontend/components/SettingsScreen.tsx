import React from 'react';

interface SettingsScreenProps {
  projectId: string;
  onBack: () => void;
}

const SettingsScreen: React.FC<SettingsScreenProps> = ({ projectId, onBack }) => {
  return (
    <div className="flex-1 flex flex-col bg-[#0d1117] overflow-hidden">
      {/* Placeholder - Full implementation in next task */}
      <div className="flex-1 flex items-center justify-center">
        <div className="text-center">
          <div className="w-16 h-16 bg-slate-800/50 rounded-2xl flex items-center justify-center mb-4 mx-auto">
            <svg className="w-8 h-8 text-slate-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M10.325 4.317c.426-1.756 2.924-1.756 3.35 0a1.724 1.724 0 002.573 1.066c1.543-.94 3.31.826 2.37 2.37a1.724 1.724 0 001.065 2.572c1.756.426 1.756 2.924 0 3.35a1.724 1.724 0 00-1.066 2.573c.94 1.543-.826 3.31-2.37 2.37a1.724 1.724 0 00-2.572 1.065c-.426 1.756-2.924 1.756-3.35 0a1.724 1.724 0 00-2.573-1.066c-1.543.94-3.31-.826-2.37-2.37a1.724 1.724 0 00-1.065-2.572c-1.756-.426-1.756-2.924 0-3.35a1.724 1.724 0 001.066-2.573c-.94-1.543.826-3.31 2.37-2.37.996.608 2.296.07 2.572-1.065z" />
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M15 12a3 3 0 11-6 0 3 3 0 016 0z" />
            </svg>
          </div>
          <h2 className="text-lg font-bold text-slate-400 mb-2">Settings</h2>
          <p className="text-sm text-slate-600 mb-4">
            Full-screen settings interface coming soon.
          </p>
          <button 
            onClick={onBack}
            className="px-4 py-2 text-xs font-bold text-felix-400 border border-felix-500/20 rounded-lg hover:bg-felix-500/10 transition-colors"
          >
            ← Back to Projects
          </button>
        </div>
      </div>
    </div>
  );
};

export default SettingsScreen;
