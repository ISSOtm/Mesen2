#pragma once
#include "stdafx.h"
#include "Utilities/ISerializable.h"
#include "Utilities/blip_buf.h"
#include "NesTypes.h"

class NesConsole;
class SoundMixer;
class EmuSettings;

class NesSoundMixer : public ISerializable
{
public:
	static constexpr uint32_t CycleLength = 10000;
	static constexpr uint32_t BitsPerSample = 16;

private:
	static constexpr uint32_t MaxSampleRate = 96000;
	static constexpr uint32_t MaxSamplesPerFrame = MaxSampleRate / 60 * 4 * 2; //x4 to allow CPU overclocking up to 10x, x2 for panning stereo
	static constexpr uint32_t MaxChannelCount = 11;

	NesConsole* _console;
	EmuSettings* _settings;
	SoundMixer* _mixer;
	double _fadeRatio;
	uint32_t _muteFrameCount;
	/*unique_ptr<OggMixer> _oggMixer;

	unique_ptr<orfanidis_eq::freq_grid> _eqFrequencyGrid;
	unique_ptr<orfanidis_eq::eq1> _equalizerLeft;
	unique_ptr<orfanidis_eq::eq1> _equalizerRight;
	shared_ptr<Console> _console;

	CrossFeedFilter _crossFeedFilter;
	LowPassFilter _lowPassFilter;
	StereoPanningFilter _stereoPanning;
	StereoDelayFilter _stereoDelay;
	StereoCombFilter _stereoCombFilter;
	ReverbFilter _reverbFilter;*/

	int16_t _previousOutputLeft = 0;
	int16_t _previousOutputRight = 0;

	vector<uint32_t> _timestamps;
	int16_t _channelOutput[MaxChannelCount][CycleLength];
	int16_t _currentOutput[MaxChannelCount];

	blip_t* _blipBufLeft;
	blip_t* _blipBufRight;
	int16_t* _outputBuffer;
	double _volumes[MaxChannelCount];
	double _panning[MaxChannelCount];

	NesModel _model;
	uint32_t _sampleRate;
	uint32_t _clockRate;

	bool _hasPanning;

	double GetChannelOutput(AudioChannel channel, bool forRightChannel);
	int16_t GetOutputVolume(bool forRightChannel);
	void EndFrame(uint32_t time);

	void UpdateRates(bool forceUpdate);
	
public:
	NesSoundMixer(shared_ptr<NesConsole> console);
	~NesSoundMixer();

	void SetNesModel(NesModel model);
	void Reset();

	void PlayAudioBuffer(uint32_t cycle);
	void AddDelta(AudioChannel channel, uint32_t time, int16_t delta);

	//For NSF/NSFe
	uint32_t GetMuteFrameCount();
	void ResetMuteFrameCount();
	void SetFadeRatio(double fadeRatio);

	//OggMixer* GetOggMixer();

	void Serialize(Serializer& s) override;
};