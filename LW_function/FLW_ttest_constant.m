classdef FLW_ttest_constant<CLW_permutation
    properties
        FLW_TYPE=1;
        h_constant_edit;
        h_tail_pop;
    end
    
    methods
        function obj = FLW_ttest_constant(batch_handle)
            obj@CLW_permutation(batch_handle,'ttest','ttest',...
                'point by point one-sample t-test with cluster based permutation test.');
            
            uicontrol('style','text','position',[35,490,200,20],...
                'string','Type of alternative hypothsis:','HorizontalAlignment','left',...
                'parent',obj.h_panel);
            obj.h_tail_pop=uicontrol('style','popupmenu','value',1,...
                'String',{'two-tailed test','left-tailed test','right-tailed test'},...
                'position',[35,465,200,30],'parent',obj.h_panel);
            
            uicontrol('style','text','position',[35,435,200,20],...
                'string','Compare to constant','HorizontalAlignment','left',...
                'parent',obj.h_panel);
            obj.h_constant_edit=uicontrol('style','edit','String','0',...
                'position',[35,415,200,25],'parent',obj.h_panel);
        end
        
        function option=get_option(obj)
            option=get_option@CLW_permutation(obj);
            option.constant=str2num(get(obj.h_constant_edit,'string'));
            switch get(obj.h_tail_pop,'value')
                case 1
                    option.tails='both';
                case 2
                    option.tails='left';
                case 3
                    option.tails='right';
            end
        end
        
        function set_option(obj,option)
            set_option@CLW_permutation(obj,option);
            set(obj.h_constant_edit,'string',num2str(option.constant));
            switch(option.tails)
                case 'both'
                    set(obj.h_tail_pop,'value',1)
                case 'left'
                    set(obj.h_tail_pop,'value',2)
                case 'right'
                    set(obj.h_tail_pop,'value',3)
            end
        end
        
        function str=get_Script(obj)
            option=get_option(obj);
            frag_code=[];
            frag_code=[frag_code,'''constant'',',...
                num2str(option.constant),','];
            frag_code=[frag_code,'''tails'',''',...
                option.tails,''','];
            frag_code=[frag_code,get_Script@CLW_permutation(obj)];
            str=get_Script@CLW_generic(obj,frag_code,option);
        end
    end
    
    methods (Static = true)
        function header_out= get_header(header_in,option)
            if header_in.datasize(1)==1
                error('There is only one epoch in the dataset!');
            end
            header_out=header_in;
            
            header_out.datasize(1)=1;
            header_out.index_labels{1}='p-value';
            header_out.index_labels{2}='t-value';
            if option.permutation==1
                header_out.datasize(3)=3;
                header_out.index_labels{3}='cluster t-value';
                if ~option.cluster_union
                    header_out.datasize(3)=4;
                    header_out.index_labels{4}='cluster p-value';
                end
            else
                header_out.datasize(3)=2;
            end
            if ~isempty(option.affix)
                header_out.name=[option.affix,' ',header_out.name];
            end
            option.function=mfilename;
            header_out.history(end+1).option=option;
        end
        
        function lwdata_out=get_lwdata(lwdata_in,varargin)
            option.constant=0;
            option.tails='both';
            option.alpha=0.05;
            option.permutation=0;
            option.num_permutations=2000;
            option.cluster_threshold=0.05;
            option.show_progress=1;
            option.cluster_union=0;
            option.multiple_sensor=0;
            option.chan_dist=0;
            
            option.affix='ttest';
            option.is_save=0;
            option=CLW_check_input(option,{'constant','tails','alpha',...
                'permutation','num_permutations','cluster_statistic',...
                'cluster_threshold','show_progress','cluster_union',...
                'multiple_sensor','chan_dist','affix','is_save'},...
                varargin);
            header=FLW_ttest_constant.get_header(lwdata_in.header,option);
            
            
            h_line=-1;
            chan_used=find([header.chanlocs.topo_enabled]==1, 1);
            if isempty(chan_used)
                S=load('init_parameter.mat');
                temp=CLW_edit_electrodes(header,S.userdata.chanlocs);
                clear S;
                [y,x]= pol2cart(pi/180.*[temp.chanlocs.theta],[temp.chanlocs.radius]);
            else
                [y,x]= pol2cart(pi/180.*[header.chanlocs.theta],[header.chanlocs.radius]);
            end
            dist=squareform(pdist([x;y]'))<option.chan_dist;
            
            if option.permutation && option.num_permutations>=2^(size(lwdata_in.data,1)-1)
                option.num_permutations=2^(size(lwdata_in.data,1)-1);
            end
            
            data=zeros(header.datasize);
            for z_idx=1:header.datasize(4)
                if option.multiple_sensor==0
                    for ch_idx=1:1:header.datasize(2)
                        data_tmp=lwdata_in.data(:,ch_idx,1,z_idx,:,:)-option.constant;
                        [~,P,~,STATS]=ttest(data_tmp,0,option.alpha,option.tails);
                        data(:,ch_idx,1,z_idx,:,:)=P;
                        data(:,ch_idx,2,z_idx,:,:)=STATS.tstat;
                        
                        
                        curve=[];
                        if option.permutation==1
                            if sum(P(:)<=option.alpha)==0
                                data(:,ch_idx,3,z_idx,:,:)=0;
                                if ~option.cluster_union
                                    data(:,ch_idx,4,z_idx,:,:)=1;
                                end
                                continue;
                            end
                            
                            if option.cluster_union
                                t_threshold=STATS.tstat(P(:)>option.alpha/...
                                    (header.datasize(5)*header.datasize(6))...
                                    & P(:)<option.alpha);
                                if isempty(t_threshold)
                                    [~,idx]=max(P(:)<option.alpha);
                                    t_threshold=STATS.tstat(idx);
                                end
                                t_threshold=sort(abs(reshape(t_threshold,[],1)));
                            else
                                if strcmp(option.tails,'both')
                                    t_threshold = abs(tinv(option.alpha/2,size(data_tmp,1)-1));
                                else
                                    t_threshold = abs(tinv(option.alpha,size(data_tmp,1)-1));
                                end
                            end
                            
                            cluster_distribute=zeros(length(t_threshold),option.num_permutations);
                            for iter=1:option.num_permutations
                                if option.num_permutations==2^(size(data_tmp,1)-1)
                                    A=dec2bin(iter)-'0';   A=[zeros(1,size(data_tmp,1)-length(A)),A];
                                else
                                    A=sign(randn(size(data_tmp,1),1));
                                end
                                rnd_data=data_tmp;
                                rnd_data(A==1,:)=-rnd_data(A==1,:);
                                tstat=mean(rnd_data)./(std(rnd_data)./sqrt(size(rnd_data,1)));
                                tstat=permute(tstat,[6,5,1,2,3,4]);
                                max_tstat=zeros(length(t_threshold),1);
                                for t_threshold_idx=1:length(t_threshold)
                                    switch option.tails
                                        case 'both'
                                            max_tstat(t_threshold_idx)=max(...
                                                CLW_max_cluster(tstat.*(tstat>=t_threshold(t_threshold_idx))),...
                                                CLW_max_cluster(-tstat.*(tstat<=-t_threshold(t_threshold_idx))));
                                        case 'left'
                                            max_tstat(t_threshold_idx)=...
                                                CLW_max_cluster(-tstat.*(tstat<=-t_threshold(t_threshold_idx)));
                                        case 'right'
                                            max_tstat(t_threshold_idx)=...
                                                CLW_max_cluster(tstat.*(tstat>=t_threshold(t_threshold_idx)));
                                    end
                                end
                                cluster_distribute(:,iter)=max_tstat;
                                
                                
                                if option.show_progress
                                    criticals=prctile(cluster_distribute(1,1:iter),(1-option.cluster_threshold)*100);
                                    curve=[curve,reshape(criticals,[],1)];
                                    if ~ishandle(h_line)
                                        figure();
                                        h_line=plot(1:iter,curve);
                                        xlim([1,option.num_permutations]);
                                    else
                                        set(h_line,'XData',1:iter,'YData',curve);
                                        str=['channel: ',num2str(ch_idx),'/',num2str(header.datasize(2))];
                                        if header.datasize(4)>1
                                            str=[str,' z:',num2str(z_idx),'/',num2str(header.datasize(4))];
                                        end
                                        title(get(h_line,'parent'),str);
                                    end
                                    drawnow;
                                end
                            end
                            %plot(sort(cluster_distribute(1,:),'descend'));
                            tstat=permute(STATS.tstat,[6,5,1,2,3,4]);
                            
                            data_tmp=ones(size(tstat));
                            for t_threshold_idx=1:length(t_threshold)
                                threshold_tmp=t_threshold(t_threshold_idx);
                                switch option.tails
                                    case 'both'
                                        data_tmp=data_tmp.*...
                                            CLW_detect_cluster(tstat.*(tstat>=threshold_tmp),...
                                            option,cluster_distribute(t_threshold_idx,:));
                                        data_tmp=data_tmp.*...
                                            CLW_detect_cluster(-tstat.*(tstat<=-threshold_tmp),...
                                            option,cluster_distribute(t_threshold_idx,:));
                                    case 'left'
                                        data_tmp=data_tmp.*...
                                            CLW_detect_cluster(-tstat.*(tstat<=-threshold_tmp),...
                                            option,cluster_distribute(t_threshold_idx,:));
                                    case 'right'
                                        data_tmp=data_tmp.*...
                                            CLW_detect_cluster(tstat.*(tstat>=threshold_tmp),...
                                            option,cluster_distribute(t_threshold_idx,:));
                                end
                            end
                            data_tmp=ipermute(data_tmp,[6,5,1,2,3,4]);
                            data(:,ch_idx,3,z_idx,:,:)=(data_tmp<1)...
                                .*data(:,ch_idx,2,z_idx,:,:);
                            if ~option.cluster_union
                                data(:,ch_idx,4,z_idx,:,:)=data_tmp;
                            end
                        end
                    end
                else
                    for ch_idx=1:1:header.datasize(2)
                        data_tmp=lwdata_in.data(:,ch_idx,1,z_idx,:,:)-option.constant;
                        [~,P,~,STATS]=ttest(data_tmp,0,option.alpha,option.tails);
                        data(:,ch_idx,1,z_idx,:,:)=P;
                        data(:,ch_idx,2,z_idx,:,:)=STATS.tstat;
                    end
                    
                    if sum(reshape(data(:,:,1,z_idx,:,:),[],1)<=option.alpha)==0
                        data(:,:,3,z_idx,:,:)=0;
                        if ~option.cluster_union
                            data(:,:,4,z_idx,:,:)=1;
                        end
                        continue;
                    end
                    curve=[];
                    if option.cluster_union
                        t_threshold=data(:,:,1,z_idx,:,:);
                        idx_temp= t_threshold>option.alpha/...
                            (header.datasize(2)*header.datasize(5)*header.datasize(6))...
                            & t_threshold<option.alpha;
                        if isempty(idx_temp)
                            [~,idx_temp]=max(t_threshold(:)<option.alpha);
                        end
                        t_threshold=data(:,:,2,z_idx,:,:);
                        t_threshold=t_threshold(idx_temp);
                        t_threshold=sort(abs(reshape(t_threshold,[],1)));
                    else
                        if strcmp(option.tails,'both')
                            t_threshold = abs(tinv(option.alpha/2,size(data_tmp,1)-1));
                        else
                            t_threshold = abs(tinv(option.alpha,size(data_tmp,1)-1));
                        end
                        
                    end
                    
                    data_tmp=lwdata_in.data(:,:,1,z_idx,:,:)-option.constant;
                    cluster_distribute=zeros(length(t_threshold),option.num_permutations);
                    for iter=1:option.num_permutations
                        if option.num_permutations==2^(size(data_tmp,1)-1)
                            A=dec2bin(iter)-'0';   A=[zeros(1,size(data_tmp,1)-length(A)),A];
                        else
                            A=sign(randn(size(data_tmp,1),1));
                        end
                        rnd_data=data_tmp;
                        rnd_data(A==1,:)=-rnd_data(A==1,:);
                        tstat=mean(rnd_data)./(std(rnd_data)./sqrt(size(rnd_data,1)));
                        tstat=permute(tstat,[6,5,1,2,3,4]);
                        max_tstat=zeros(length(t_threshold),1);
                        for t_threshold_idx=1:length(t_threshold)
                            switch option.tails
                                case 'both'
                                    max_tstat(t_threshold_idx)=max(...
                                        CLW_max_cluster(tstat.*(tstat>=t_threshold(t_threshold_idx)),dist),...
                                        CLW_max_cluster(-tstat.*(tstat<=-t_threshold(t_threshold_idx)),dist));
                                case 'left'
                                    max_tstat(t_threshold_idx)=...
                                        CLW_max_cluster(-tstat.*(tstat<=-t_threshold(t_threshold_idx)),dist);
                                case 'right'
                                    max_tstat(t_threshold_idx)=...
                                        CLW_max_cluster(tstat.*(tstat>=t_threshold(t_threshold_idx)),dist);
                            end
                        end
                        cluster_distribute(:,iter)=max_tstat;
                        
                        
                        if option.show_progress
                            criticals=prctile(cluster_distribute(1,1:iter),(1-option.cluster_threshold)*100);
                            curve=[curve,reshape(criticals,[],1)];
                            if ~ishandle(h_line)
                                figure();
                                h_line=plot(1:iter,curve);
                                xlim([1,option.num_permutations]);
                            else
                                set(h_line,'XData',1:iter,'YData',curve);
                                if header.datasize(4)>1
                                    str=[' z:',num2str(z_idx),'/',num2str(header.datasize(4))];
                                    title(get(h_line,'parent'),str);
                                end
                            end
                            drawnow;
                        end
                    end
                    
                    tstat=permute(data(:,:,2,z_idx,:,:),[6,5,1,2,3,4]);
                    data_tmp=ones(size(tstat));
                    for t_threshold_idx=1:length(t_threshold)
                        threshold_tmp=t_threshold(t_threshold_idx);
                        switch option.tails
                            case 'both'
                                data_tmp=data_tmp.*...
                                    CLW_detect_cluster(tstat.*(tstat>threshold_tmp),...
                                    option,cluster_distribute(t_threshold_idx,:),dist);
                                data_tmp=data_tmp.*...
                                    CLW_detect_cluster(-tstat.*(tstat<-threshold_tmp),...
                                    option,cluster_distribute(t_threshold_idx,:),dist);
                            case 'left'
                                data_tmp=data_tmp.*...
                                    CLW_detect_cluster(-tstat.*(tstat<-threshold_tmp),...
                                    option,cluster_distribute(t_threshold_idx,:),dist);
                            case 'right'
                                data_tmp=data_tmp.*...
                                    CLW_detect_cluster(tstat.*(tstat>threshold_tmp),...
                                    option,cluster_distribute(t_threshold_idx,:),dist);
                        end
                    end
                    
                    data_tmp=ipermute(data_tmp,[6,5,1,2,3,4]);
                    data(:,:,3,z_idx,:,:)=(data_tmp<1).*data(:,:,2,z_idx,:,:);
                    if ~option.cluster_union
                        data(:,:,4,z_idx,:,:)=data_tmp;
                    end
                end
            end
            
            lwdata_out.header=header;
            lwdata_out.data=data;
            if option.is_save
                CLW_save(lwdata_out);
            end
            if option.permutation && option.show_progress
                if ishandle(h_line)
                    close(get(get(h_line,'parent'),'parent'));
                end
            end
        end
        
    end
end