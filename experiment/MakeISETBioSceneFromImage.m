function [ISETBioGaborObject] = MakeISETBioSceneFromImage(colorDirectionParams,gaborImageObject,standardGaborCalObject,...
    ISETBioDisplayObject,stimulusHorizSizeMeters,stimulusHorizSizeDeg,options)
% Make ISETBio scene from the gabor image.
%
% Syntax:
%    [ISETBioGaborCalObject] = MakeISETBioSceneFromImage(colorDirectionParams,gaborImageObject,standardGaborCalObject,...
%                              ISETBioDisplayObject,stimulusHorizSizeMeters,stimulusHorizSizeDeg)
%
% Description:
%    This puts the target gabor image into ISETBio scene.
%
% Inputs:
%    colorDirectionParams          - Structure with the parameters to
%                                    calculate a contrast gabor image.
%    gaborImageObject              - Structure with the gabor contrast image in
%                                    image format.
%    standardGaborCalObject        - Structure with the gabor contrasts
%                                    and settings in a cal format.
%    ISETBioDisplayObject          - Structure with the parameters to make the
%                                    ISETBio scene from image.
%    stimulusHorizSizeMeters       - The horizontal size of the gabor image
%                                    in meters.
%    stimulusHorizSizeDeg          - The horizontal size of the gabor image
%                                    in degrees.
%
% Outputs:
%    ISETBioGaborObject            - Structure with gabor contrast image in
%                                    the ISETBio scene format.
%
% Optional key/value pairs:
%    verbose                       - Boolean. Default true. Controls
%                                    plotting and printout.
%
% See also:
%    SpectralCalCompute, SpectralCalCheck, SpectralCalAnalyze,
%    SpectralCalISETBio, GetSettingsFromISETBioScene

% History:
%   01/21/22  dhb,gka,smo     - Wrote it.
%   01/24/22  smo             - Made it work.
%   01/31/22  smo             - It is possible to work on multiple
%                               target contrast gabors inside this
%                               function.
%   05/09/22  smo             - Added an option to make a phase shift on
%                               sine image.
%   09/06/23  dhb             - Use T_receptor field to compute responses
%                               if it exists. Defaults back to T_cones if
%                               T_receptor field is not there.  This change
%                               to handle simulations/experiments with
%                               melanopsin.

%% Set parameters.
arguments
    colorDirectionParams
    gaborImageObject
    standardGaborCalObject
    ISETBioDisplayObject
    stimulusHorizSizeMeters
    stimulusHorizSizeDeg
    options.verbose (1,1) = true
    options.MTF_SACCSFA (:,:) = [] % Accepts any size matrix, default is empty
end

%% Put the image into an ISETBio scene.
%
% These calls are a bit slow for large images and the fine wavelength
% sampling used here. But these would be done as pre-compute steps so
% it doesn't seem worth trying to optimize at this point.
nContrastPoints = size(gaborImageObject.standardSettingsGaborImage,2);
nPhaseShifts = size(gaborImageObject.standardSettingsGaborImage,1);

for ss = 1:nPhaseShifts
    for cc = 1:nContrastPoints
        % Make ISETBio scene from the gabor image.
        ISETBioGaborScene = sceneFromFile(gaborImageObject.standardSettingsGaborImage{ss,cc},'rgb', [], ISETBioDisplayObject);
        %clear this huge variable to save some memory
        clear gaborImageObject
        % apply MTF
        if ~isempty(options.MTF_SACCSFA)
            % ISETBioGaborScene_without_MTF = ISETBioGaborScene;
            func_contrast = @(l) (max(l(:)) - min(l(:)))/(max(l(:)) + min(l(:)));
            %retrieve the photons
            photons_f = sceneGet(ISETBioGaborScene, 'photons');
            wvl = sceneGet(ISETBioGaborScene, 'wave');
            
            %initialize
            photons_f_adjusted = NaN(size(photons_f));
            [contrast_MTF_uncorrected, contrast_MTF_corrected_theoretical, contrast_MTF_corrected_actual] = ...
                deal(NaN(1, length(wvl)));
            for w = 1:length(wvl)
                % Extract the image slice for the current wavelength
                photons_f_w = photons_f(:,:,w);
            
                % Calculate Michelson contrast for this wavelength
                contrast_MTF_uncorrected(w) = func_contrast(photons_f_w);
                contrast_MTF_corrected_theoretical(w) = contrast_MTF_uncorrected(w)* options.MTF_SACCSFA(w);
        
                photons_f_adjusted(:,:,w) = (photons_f_w - mean(photons_f_w(:))).* options.MTF_SACCSFA(w) + mean(photons_f_w(:));
                contrast_MTF_corrected_actual(w) = func_contrast(photons_f_adjusted(:,:,w));
            end
            %stick photons back to the scene
            ISETBioGaborScene.data.photons = photons_f_adjusted;
            
            % visualizations for debugging
            if options.verbose
                figure; scatter(contrast_MTF_corrected_theoretical, contrast_MTF_corrected_actual); grid on; axis square
                xlabel('Predicted modified contrast'); ylabel('Actual modified contrast');

                mid_row = ceil(size(photons_f,1)/2);
                slc_wvl =  [81,101,121];
                figure;
                for ww = 1:length(slc_wvl)
                    subplot(3,1,ww)
                    plot(200:750, photons_f(mid_row, 200:750, slc_wvl(ww)), 'k','LineWidth',2); hold on
                    plot(200:750,photons_f_adjusted(mid_row, 200:750,slc_wvl(ww)), 'g','LineWidth',1);
                    title(sprintf('Wvl: %.0f nm', wvl(slc_wvl(ww)))); xlim([200,750]);
                end
            end
        end
        
        % Show the image on ISETBio scene window.
        if (options.verbose)
            sceneWindow(ISETBioGaborScene);
        end
        
        % Check stimulus dimensions match. These are good to about a percent, which
        % we can live with.
        stimulusHorizSizeMetersChk = sceneGet(ISETBioGaborScene,'width');
        stimulusHorizSizeDegChk = sceneGet(ISETBioGaborScene,'horizontal fov');
        if (abs(stimulusHorizSizeMeters - stimulusHorizSizeMetersChk)/stimulusHorizSizeMeters > 0.01)
            error('Horizontal size in meters mismatch of too much');
        end
        if (abs(stimulusHorizSizeDeg - stimulusHorizSizeDegChk)/stimulusHorizSizeDeg > 0.01)
            error('Horizontal size in deg mismatch of too much');
        end
        
        %% Calculate cone excitations from the ISETBio scene.
        % These should match what we get when we compute
        % outside of ISETBio. And indeed!
        %
        % ISETBio energy comes back as power per nm, we need to convert to power
        % per wlband to work with PTB, by multiplying by S(2).
        ISETBioGaborImage = sceneGet(ISETBioGaborScene,'energy') * colorDirectionParams.S(2);
        [ISETBioGaborCal,~,~] = ImageToCalFormat(ISETBioGaborImage);
        if (isfield(colorDirectionParams,'T_receptors'))
            ISETBioPredictedExcitationsGaborCal = colorDirectionParams.T_receptors * ISETBioGaborCal;
        else
            ISETBioPredictedExcitationsGaborCal = colorDirectionParams.T_cones * ISETBioGaborCal;
        end
        
        % Plot it to comapare the cone excitations between before and after passing
        % the ISETBio scene.
        if (options.verbose)
            figure; clf; hold on;
            plot(standardGaborCalObject.standardPredictedExcitationsGaborCal{ss,cc}(1,:), ISETBioPredictedExcitationsGaborCal(1,:),'r+');
            plot(standardGaborCalObject.standardPredictedExcitationsGaborCal{ss,cc}(2,:), ISETBioPredictedExcitationsGaborCal(2,:),'g+');
            plot(standardGaborCalObject.standardPredictedExcitationsGaborCal{ss,cc}(3,:), ISETBioPredictedExcitationsGaborCal(3,:),'b+');
            %limMin = 0.01; limMax = 0.02;
            %plot([limMin limMax], [limMin limMax]);
            xlabel('Standard Cone Excitations');
            ylabel('ISETBio Cone Excitations');
            axis('square'); %xlim([limMin limMax]); ylim([limMin limMax]);
            title('Cone Excitations Comparison');
        end
        
        % Check if it predicts well
        % If we apply the display's MTF, it will definitely not pass the
        % following check, so skip it.
        if isempty(options.MTF_SACCSFA)
            if (max(abs(standardGaborCalObject.standardPredictedExcitationsGaborCal{ss,cc}(:) - ISETBioPredictedExcitationsGaborCal(:)) ./ ...
                    standardGaborCalObject.standardPredictedExcitationsGaborCal{ss,cc}(:)) > 1e-5)
                error('Standard and ISETBio data do not agree well enough');
            end
        end
        
        % Save the results in a struct.
        % ISETBioGaborObject.ISETBioGaborScene_without_MTF{ss,cc} = ISETBioGaborScene_without_MTF;
        ISETBioGaborObject.ISETBioGaborScene{ss,cc} = ISETBioGaborScene;
        ISETBioGaborObject.ISETBioGaborImage{ss,cc} = ISETBioGaborImage;
        ISETBioGaborObject.ISETBioPredictedExcitationsGaborCal{ss,cc} = ISETBioPredictedExcitationsGaborCal;
        ISETBioGaborObject.ISETBioGaborCal{ss,cc} = ISETBioGaborCal;
        
        % Print out if everything goes well.
        if (options.verbose)
            disp('Gabor image has been successfully calculated from the ISETBio scene!');
        end
    end
end
end
