classdef Constellation < handle

    properties
        totalSatCount = 0;
        groups = {};
        state;

        % константы
        earthRadius = 6378135;           % Экваториальный радиус Земли [m]
        earthGM = 3.986004415e+14;       % Гравитационный параметр Земли [m3/s2]
        earthJ2 = 1.082626e-3;           % Вторая зональная гармоника геопотенциала
    end

    methods

        function this = Constellation(varargin)
            if isempty(varargin)
                return
            end
            this.loadFromConfigFile(varargin{1});
        end

        function loadFromConfigFile(this, code)
            fileName = '../constellationsTest.json';
            str = fileread(fileName);
            data = jsondecode(str);
            dataThis = [];

            for i = 1:length(data)
                if strcmpi(data(i).name, code)
                    dataThis = data(i);
                    break
                end
            end

            if isempty(dataThis)
                disp('Группировка не найдена в файле');
                return
            end

            for i = 1:size(dataThis.Walkers, 1)
                group.inclination = deg2rad(dataThis.Walkers(i, 1));        % наклонение орбитальной плоскости
                group.satsPerPlane = dataThis.Walkers(i, 2);				% число КА в каждой орбитальной плоскости группы
                group.planeCount = dataThis.Walkers(i, 3);					% число орбитальных плоскостей в группе
                group.f = dataThis.Walkers(i, 4);							% фазовый сдвиг по аргументу широты между КА в соседних плоскостях
                group.altitude = dataThis.Walkers(i, 5);					% высота орбиты
                group.maxRaan = deg2rad(dataThis.Walkers(i, 6));            % максимум прямого восхождения восходящего узла (при распределении орбитальных плоскостей)
                group.startRaan = deg2rad(dataThis.Walkers(i, 7));			% прямое восхождение восходящего узла для первой плоскости
                group.totalSatCount = group.satsPerPlane * group.planeCount;

                this.groups{length(this.groups) + 1} = group;                
                this.totalSatCount = this.totalSatCount + group.totalSatCount;
            end
        end

        function getInitialState(this)
            this.state.elements = zeros(this.totalSatCount, 6);
            shift = 1;

            for group = this.groups
                for i = 1:length(group{1})
                    ending = shift + group{1}(i).totalSatCount - 1;
                    this.state.elements(shift:ending,:) = this.getInitialElements(group{1});
                    shift = ending + 1;
                end
            end
        end

        function elements = getInitialElements(this, group)
            raans = linspace(group.startRaan, group.startRaan + group.maxRaan, group.planeCount + 1);
            raans = mod(raans(1:end-1), 2 * pi);

            elements = zeros(group.totalSatCount, 6);
            idx = 1;
            raanIDX = 0;
            for raan = raans
                for i = 0:group.satsPerPlane-1
                    sma = this.earthRadius + group.altitude * 1000;
                    aol = 2 * pi / group.satsPerPlane * i + 2 * pi / group.totalSatCount * group.f * raanIDX;

                    elements(idx, :) = [sma, 0, 0, raan, group.inclination, aol];
                    idx = idx + 1;
                end
                raanIDX = raanIDX + 1;
            end
        end        

        function propagateJ2(this, epochs)
            this.state.eci = zeros(this.totalSatCount, 3, length(epochs));

            sma         = this.state.elements(:, 1);
            inclination = this.state.elements(:, 5);            
            raan0       = this.state.elements(:, 4);
            aol0        = this.state.elements(:, 6);

            raanPrecessionRate = -1.5 * (this.earthJ2 * this.earthGM^(1/2) * this.earthRadius^2) ./ (sma.^(7/2)) .* cos(inclination);
            draconicOmega      = sqrt(this.earthGM ./ sma.^3) .* (1 - 1.5 * this.earthJ2 .* (this.earthRadius ./ sma).^2) .* (1 - 4 .* cos(inclination).^2);

            for epochIdx = 1:length(epochs)
                aol = aol0 + epochs(epochIdx) * draconicOmega;
                raanOmega = raan0 + epochs(epochIdx) * raanPrecessionRate;

                this.state.eci(:, :, epochIdx)  = [sma .* (cos(aol) .* cos(raanOmega) - sin(aol) .* cos(inclination) .* sin(raanOmega)), ...
                                                   sma .* (cos(aol) .* sin(raanOmega) + sin(aol) .* cos(inclination) .* cos(raanOmega)), ...
                                                   sma .* (sin(aol) .* sin(inclination))];
            end
        end
    end
end
